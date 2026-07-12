import { Injectable, Logger } from '@nestjs/common';
import * as pdfMake from 'pdfmake';
import { PrismaService } from '../common/prisma/prisma.service';
import {
  Document,
  Packer,
  Paragraph,
  Table,
  TableRow,
  TableCell,
  TextRun,
  HeadingLevel,
  WidthType,
} from 'docx';
import { ReportingService } from './reporting.service';
import { ReportFilterDto, ReportPeriod } from './dto/reporting.dto';
import {
  GenerateReportDto,
  GeneratedReport,
  ReportExportFormat,
  ReportExportType,
  ReportSection,
} from './dto/report-export.dto';

const money = (n: number | undefined | null) =>
  `KES ${Math.round(Number(n) || 0).toLocaleString('en-KE')}`;

const PERIOD_LABEL: Record<ReportPeriod, string> = {
  [ReportPeriod.TODAY]: 'Today',
  [ReportPeriod.YESTERDAY]: 'Yesterday',
  [ReportPeriod.THIS_WEEK]: 'This Week',
  [ReportPeriod.LAST_WEEK]: 'Last Week',
  [ReportPeriod.THIS_MONTH]: 'This Month',
  [ReportPeriod.LAST_MONTH]: 'Last Month',
  [ReportPeriod.THIS_QUARTER]: 'This Quarter',
  [ReportPeriod.THIS_YEAR]: 'This Year',
  [ReportPeriod.CUSTOM]: 'Custom Range',
};

/**
 * Turns real DB report data into a downloadable PDF or DOCX — the AI chat's
 * "give me a PDF/DOCX report" ability. Deliberately built around one generic
 * ReportSection shape (heading + headers + rows) rather than a bespoke
 * layout per report type, mirroring the mobile app's own PdfReportSection so
 * both sides of the app describe a report the same way. pdfmake and docx are
 * both pure-JS (no native binary, no headless-browser dependency like
 * puppeteer would need), matching this backend's existing deploy footprint.
 */
@Injectable()
export class ReportExportService {
  private readonly logger = new Logger(ReportExportService.name);

  constructor(
    private readonly reporting: ReportingService,
    private readonly prisma: PrismaService,
  ) {
    // Standard 14 core PDF fonts (built into pdfkit/the PDF spec) — no font
    // files to ship or host. setFonts/setUrlAccessPolicy are set once on the
    // module-level singleton; the local access policy is deliberately left
    // unset (its warning is expected) since restricting it blocks pdfkit's
    // own resolution of these built-in font names.
    pdfMake.setFonts({
      Helvetica: {
        normal: 'Helvetica',
        bold: 'Helvetica-Bold',
        italics: 'Helvetica-Oblique',
        bolditalics: 'Helvetica-BoldOblique',
      },
    });
    pdfMake.setUrlAccessPolicy(() => false);
  }

  /** Top-level entry point: builds the report data then renders it into
   * whichever format was requested, returning everything a controller (or
   * the AI tool executor) needs to send the file back. */
  async generate(
    tenantId: string,
    dto: GenerateReportDto,
  ): Promise<{ buffer: Buffer; filename: string; contentType: string }> {
    const [report, companyName] = await Promise.all([
      this.buildReportData(tenantId, dto),
      this.getCompanyName(tenantId),
    ]);

    const slug = report.title.toLowerCase().replace(/[^a-z0-9]+/g, '-');
    const datePart = new Date().toISOString().slice(0, 10);

    if (dto.format === ReportExportFormat.DOCX) {
      return {
        buffer: await this.renderDocx(report, companyName),
        filename: `${slug}-${datePart}.docx`,
        contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      };
    }

    if (dto.format === ReportExportFormat.CSV) {
      return {
        buffer: Buffer.from(this.renderCsv(report), 'utf-8'),
        filename: `${slug}-${datePart}.csv`,
        contentType: 'text/csv',
      };
    }

    return {
      buffer: await this.renderPdf(report, companyName),
      filename: `${slug}-${datePart}.pdf`,
      contentType: 'application/pdf',
    };
  }

  private async getCompanyName(tenantId: string): Promise<string> {
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { name: true },
    });
    return tenant?.name || 'Axon POS';
  }

  private renderCsv(report: GeneratedReport): string {
    const lines: string[] = [report.title, report.subtitle, ''];
    for (const section of report.sections) {
      lines.push(section.heading);
      lines.push(section.headers.map((h) => this.csvEscape(h)).join(','));
      for (const row of section.rows) {
        lines.push(row.map((c) => this.csvEscape(c)).join(','));
      }
      lines.push('');
    }
    return lines.join('\n');
  }

  private csvEscape(value: string): string {
    if (value.includes(',') || value.includes('"') || value.includes('\n')) {
      return `"${value.replace(/"/g, '""')}"`;
    }
    return value;
  }

  async buildReportData(tenantId: string, dto: GenerateReportDto): Promise<GeneratedReport> {
    const filter: ReportFilterDto = {
      period: dto.period ?? ReportPeriod.THIS_WEEK,
      branchId: dto.branchId,
    };
    const periodLabel = PERIOD_LABEL[filter.period ?? ReportPeriod.THIS_WEEK];

    switch (dto.reportType) {
      case ReportExportType.SALES_SUMMARY: {
        const summary = await this.reporting.getSalesSummary(tenantId, filter);
        return {
          title: 'Sales Summary',
          subtitle: periodLabel,
          sections: [
            {
              heading: 'Overview',
              headers: ['Metric', 'Value'],
              rows: [
                ['Total Sales', String(summary.totalSales)],
                ['Total Revenue', money(summary.totalRevenue)],
                ['Total Discount', money(summary.totalDiscount)],
                ['Net Revenue', money(summary.netRevenue)],
                ['Average Ticket', money(summary.averageTicket)],
              ],
            },
          ],
        };
      }

      case ReportExportType.TOP_PRODUCTS: {
        const products = await this.reporting.getTopProducts(tenantId, filter, 20);
        return {
          title: 'Top Products',
          subtitle: periodLabel,
          sections: [
            {
              heading: 'Best Sellers',
              headers: ['Product', 'SKU', 'Category', 'Qty Sold', 'Revenue'],
              rows: products.map((p) => [
                p.productName,
                p.sku,
                p.categoryName,
                String(p.quantitySold),
                money((p as any).revenue),
              ]),
            },
          ],
        };
      }

      case ReportExportType.PROFIT_LOSS: {
        const rows = await this.reporting.getProfitAndLossRange(tenantId, filter);
        return {
          title: 'Profit & Loss',
          subtitle: periodLabel,
          sections: [
            {
              heading: 'Daily Breakdown',
              headers: ['Date', 'Branch', 'Gross Sales', 'Discounts', 'Net Profit'],
              rows: rows.map((r) => [
                r.date,
                r.branchName,
                money(r.grossSales),
                money(r.totalDiscounts),
                money((r as any).netProfit),
              ]),
            },
          ],
        };
      }

      case ReportExportType.INVENTORY: {
        const inv = await this.reporting.getInventoryReport(tenantId, dto.branchId);
        return {
          title: 'Inventory Report',
          subtitle: dto.branchId ? 'Selected Branch' : 'All Branches',
          sections: [
            {
              heading: 'Overview',
              headers: ['Metric', 'Value'],
              rows: [
                ['Total Products', String(inv.totalProducts)],
                ['Total Stock Value', money(inv.totalStockValue)],
                ['Low Stock Items', String(inv.lowStockItems)],
                ['Out of Stock Items', String(inv.outOfStockItems)],
                ['Overstocked Items', String(inv.overStockItems)],
              ],
            },
          ],
        };
      }

      case ReportExportType.PAYMENT_BREAKDOWN: {
        const breakdown = await this.reporting.getPaymentMethodBreakdown(tenantId, filter);
        return {
          title: 'Payment Method Breakdown',
          subtitle: periodLabel,
          sections: [
            {
              heading: 'By Method',
              headers: ['Method', 'Transactions', 'Amount'],
              rows: breakdown.map((b: any) => [
                b.method,
                String(b.transactionCount ?? b.count ?? 0),
                money(b.totalAmount ?? b.amount),
              ]),
            },
          ],
        };
      }

      default:
        throw new Error(`Unknown report type: ${dto.reportType}`);
    }
  }

  async renderPdf(report: GeneratedReport, companyName: string): Promise<Buffer> {
    const content: any[] = [
      { text: companyName, style: 'company' },
      { text: report.title, style: 'title' },
      { text: report.subtitle, style: 'subtitle', margin: [0, 0, 0, 16] },
    ];

    for (const section of report.sections) {
      content.push({ text: section.heading, style: 'sectionHeading' });
      content.push(this.sectionToPdfTable(section));
    }

    const docDefinition = {
      content,
      defaultStyle: { font: 'Helvetica', fontSize: 9 },
      styles: {
        company: { fontSize: 16, bold: true, margin: [0, 0, 0, 2] },
        title: { fontSize: 12, color: '#6B7280' },
        subtitle: { fontSize: 10, color: '#6B7280' },
        sectionHeading: { fontSize: 12, bold: true, margin: [0, 12, 0, 6] },
      },
      footer: (currentPage: number, pageCount: number) => ({
        text: `Page ${currentPage} of ${pageCount}  •  Generated from Axon POS`,
        alignment: 'right',
        fontSize: 8,
        color: '#6B7280',
        margin: [0, 0, 32, 16],
      }),
      pageMargins: [32, 32, 32, 40] as [number, number, number, number],
    };

    return pdfMake.createPdf(docDefinition as any).getBuffer();
  }

  private sectionToPdfTable(section: ReportSection) {
    return {
      table: {
        headerRows: 1,
        widths: section.headers.map(() => '*'),
        body: [
          section.headers.map((h) => ({ text: h, bold: true, fillColor: '#F3F4F6' })),
          ...section.rows.map((row) => row.map((cell) => ({ text: cell }))),
        ],
      },
      layout: {
        hLineWidth: () => 0.5,
        vLineWidth: () => 0.5,
        hLineColor: () => '#E5E7EB',
        vLineColor: () => '#E5E7EB',
      },
      margin: [0, 0, 0, 12] as [number, number, number, number],
    };
  }

  async renderDocx(report: GeneratedReport, companyName: string): Promise<Buffer> {
    const children: (Paragraph | Table)[] = [
      new Paragraph({
        children: [new TextRun({ text: companyName, bold: true, size: 32 })],
      }),
      new Paragraph({
        heading: HeadingLevel.HEADING_1,
        children: [new TextRun({ text: report.title })],
      }),
      new Paragraph({
        children: [new TextRun({ text: report.subtitle, color: '6B7280' })],
        spacing: { after: 300 },
      }),
    ];

    for (const section of report.sections) {
      children.push(
        new Paragraph({
          heading: HeadingLevel.HEADING_2,
          children: [new TextRun({ text: section.heading })],
          spacing: { before: 200, after: 120 },
        }),
      );
      children.push(this.sectionToDocxTable(section));
    }

    const doc = new Document({
      sections: [{ children }],
    });

    return Packer.toBuffer(doc);
  }

  private sectionToDocxTable(section: ReportSection): Table {
    const headerRow = new TableRow({
      children: section.headers.map(
        (h) =>
          new TableCell({
            children: [new Paragraph({ children: [new TextRun({ text: h, bold: true })] })],
            shading: { fill: 'F3F4F6' },
          }),
      ),
    });

    const dataRows = section.rows.map(
      (row) =>
        new TableRow({
          children: row.map(
            (cell) =>
              new TableCell({
                children: [new Paragraph({ children: [new TextRun({ text: cell })] })],
              }),
          ),
        }),
    );

    return new Table({
      width: { size: 100, type: WidthType.PERCENTAGE },
      rows: [headerRow, ...dataRows],
    });
  }
}
