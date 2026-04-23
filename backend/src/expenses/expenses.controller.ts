import {
  Controller,
  Get,
  Post,
  Put,
  Delete,
  Body,
  Param,
  Query,
  UseGuards,
  ParseUUIDPipe,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { ExpensesService } from './expenses.service';
import {
  CreateExpenseDto,
  UpdateExpenseDto,
  ExpenseQueryDto,
  CreateExpenseWithItemsDto,
  ExpenseResponseDto,
  ExpenseSummaryDto,
  ExpenseTrendDto,
} from './dto/expenses.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';

@ApiTags('expenses')
@Controller({ path: 'expenses', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class ExpensesController {
  constructor(private readonly expensesService: ExpensesService) {}

  @Post()
  @ApiOperation({ summary: 'Create a new expense' })
  @ApiResponse({ status: 201, description: 'Expense created', type: ExpenseResponseDto })
  async createExpense(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: CreateExpenseDto,
  ) {
    return this.expensesService.createExpense(userId, tenantId, dto);
  }

  @Post('with-items')
  @ApiOperation({ summary: 'Create expense with line items' })
  @ApiResponse({ status: 201, description: 'Expense with items created', type: ExpenseResponseDto })
  async createExpenseWithItems(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: CreateExpenseWithItemsDto,
  ) {
    return this.expensesService.createExpenseWithItems(userId, tenantId, dto);
  }

  @Get()
  @ApiOperation({ summary: 'Get all expenses with filters' })
  @ApiResponse({ status: 200, description: 'List of expenses' })
  async getExpenses(
    @CurrentUser('tenantId') tenantId: string,
    @Query() query: ExpenseQueryDto,
  ) {
    return this.expensesService.getExpenses(tenantId, query);
  }

  @Get('summary')
  @ApiOperation({ summary: 'Get expense summary' })
  @ApiResponse({ status: 200, description: 'Expense summary', type: ExpenseSummaryDto })
  async getSummary(
    @CurrentUser('tenantId') tenantId: string,
    @Query('branchId') branchId?: string,
    @Query('startDate') startDate?: string,
    @Query('endDate') endDate?: string,
  ) {
    return this.expensesService.getSummary(tenantId, branchId, startDate, endDate);
  }

  @Get('trend')
  @ApiOperation({ summary: 'Get expense trend over time' })
  @ApiResponse({ status: 200, description: 'Expense trend', type: [ExpenseTrendDto] })
  async getTrend(
    @CurrentUser('tenantId') tenantId: string,
    @Query('startDate') startDate: string,
    @Query('endDate') endDate: string,
    @Query('groupBy') groupBy: 'day' | 'week' | 'month' = 'day',
  ) {
    return this.expensesService.getTrend(tenantId, startDate, endDate, groupBy);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get expense by ID' })
  @ApiResponse({ status: 200, description: 'Expense details', type: ExpenseResponseDto })
  async getExpense(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser('tenantId') tenantId: string,
  ) {
    return this.expensesService.getExpense(id, tenantId);
  }

  @Put(':id')
  @ApiOperation({ summary: 'Update an expense' })
  @ApiResponse({ status: 200, description: 'Expense updated', type: ExpenseResponseDto })
  async updateExpense(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: UpdateExpenseDto,
  ) {
    return this.expensesService.updateExpense(id, userId, tenantId, dto);
  }

  @Post(':id/approve')
  @ApiOperation({ summary: 'Approve an expense' })
  @ApiResponse({ status: 200, description: 'Expense approved', type: ExpenseResponseDto })
  async approveExpense(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body('notes') notes?: string,
  ) {
    return this.expensesService.approveExpense(id, userId, tenantId, notes);
  }

  @Post(':id/reject')
  @ApiOperation({ summary: 'Reject an expense' })
  @ApiResponse({ status: 200, description: 'Expense rejected', type: ExpenseResponseDto })
  async rejectExpense(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body('reason') reason: string,
  ) {
    return this.expensesService.rejectExpense(id, userId, tenantId, reason);
  }

  @Post(':id/mark-paid')
  @ApiOperation({ summary: 'Mark expense as paid' })
  @ApiResponse({ status: 200, description: 'Expense marked as paid', type: ExpenseResponseDto })
  async markAsPaid(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
  ) {
    return this.expensesService.markAsPaid(id, userId, tenantId);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Delete an expense' })
  @ApiResponse({ status: 204, description: 'Expense deleted' })
  async deleteExpense(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
  ) {
    await this.expensesService.deleteExpense(id, userId, tenantId);
  }
}
