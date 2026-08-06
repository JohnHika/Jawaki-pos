import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

// Huly API client — imported dynamically to avoid hard dependency at module load.
// The @hcengineering packages are peer dependencies that must be installed in the
// backend's package.json before this service can connect.
let hulyClientPkg: any, trackerPkg: any, corePkg: any, chunterPkg: any, attachmentPkg: any;

function loadHulyDeps() {
  if (hulyClientPkg) return;
  try {
    hulyClientPkg = require('@hcengineering/api-client');
    trackerPkg = require('@hcengineering/tracker');
    corePkg = require('@hcengineering/core');
    chunterPkg = require('@hcengineering/chunter');
    attachmentPkg = require('@hcengineering/attachment');
  } catch {
    // Dependencies not installed — Huly integration is disabled.
  }
}

export interface CreateBugReportInput {
  title: string;
  description: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  metadata: {
    appVersion: string;
    deviceOs: string;
    userId: string;
    currentScreen: string;
  };
  screenshotBase64?: string;
  screenshotMimeType?: string;
}

export interface CreateBugReportResult {
  success: boolean;
  hulyIssueId?: string;
  hulyUrl?: string;
  error?: string;
}

@Injectable()
export class BugReportService {
  private readonly logger = new Logger(BugReportService.name);
  private readonly hulyUrl: string;
  private readonly hulyWorkspace: string;
  private readonly hulyBotEmail: string;
  private readonly hulyBotPassword: string;
  private readonly projectIdentifier: string;
  private readonly enabled: boolean;

  constructor(private configService: ConfigService) {
    this.hulyUrl = this.configService.get<string>('HULY_URL', 'https://tickets.arche-axon.xyz');
    this.hulyWorkspace = this.configService.get<string>('HULY_WORKSPACE', 'archeaxonintelligence');
    this.hulyBotEmail = this.configService.get<string>('HULY_BOT_EMAIL', '');
    this.hulyBotPassword = this.configService.get<string>('HULY_BOT_PASSWORD', '');
    this.projectIdentifier = this.configService.get<string>('HULY_BUG_PROJECT', 'BUG');
    this.enabled = !!(this.hulyBotEmail && this.hulyBotPassword);
    if (!this.enabled) {
      this.logger.warn('HULY_BOT_EMAIL/PASSWORD not set — bug reports will be logged but not sent to Huly');
    }
  }

  async createBugReport(input: CreateBugReportInput): Promise<CreateBugReportResult> {
    if (!this.enabled) {
      this.logger.log(`Bug report (Huly disabled): ${input.title}`);
      return { success: false, error: 'Bug reporting service is not configured. Please contact support.' };
    }

    loadHulyDeps();
    if (!hulyClientPkg) {
      this.logger.error('Huly API client packages not installed');
      return { success: false, error: 'Bug reporting backend is not fully set up.' };
    }

    try {
      const apiClient = (hulyClientPkg as any).default ?? hulyClientPkg;
      const { connectRest } = apiClient;
      const tracker = ((trackerPkg as any).default ?? trackerPkg) as any;
      const core = corePkg as any;
      const chunter = ((chunterPkg as any).default ?? chunterPkg) as any;
      const attachment = ((attachmentPkg as any).default ?? attachmentPkg) as any;

      // Connect to Huly
      const restClient = await connectRest(this.hulyUrl, {
        email: this.hulyBotEmail,
        password: this.hulyBotPassword,
        workspace: this.hulyWorkspace,
      });
      const account = await restClient.getAccount();
      const { hierarchy } = await restClient.getModel();
      restClient.getHierarchy = () => hierarchy;
      const txClient = new core.TxOperations(restClient, account.primarySocialId);

      // Resolve the project
      const project = await txClient.findOne(tracker.class.Project, { identifier: this.projectIdentifier });
      if (project === undefined) {
        return { success: false, error: `Huly project "${this.projectIdentifier}" not found.` };
      }

      // Build the report text with metadata
      const reportText = [
        `## Description`,
        input.description,
        ``,
        `## Metadata`,
        `- **App Version:** ${input.metadata.appVersion}`,
        `- **Device/OS:** ${input.metadata.deviceOs}`,
        `- **User ID:** ${input.metadata.userId}`,
        `- **Screen:** ${input.metadata.currentScreen}`,
        `- **Severity:** ${input.severity.toUpperCase()}`,
      ].join('\n');

      // Increment project sequence
      await txClient.updateDoc(tracker.class.Project, 'core:space:Space', project._id, { $inc: { sequence: 1 } }, true);
      const updated = await txClient.findOne(tracker.class.Project, { _id: project._id });
      const number: number = updated?.sequence ?? 1;
      const identifier = `${this.projectIdentifier}-${number}`;
      const issueId = core.generateId();

      // Create the issue
      await txClient.addCollection(
        tracker.class.Issue,
        project._id,
        tracker.ids.NoParent,
        tracker.class.Issue,
        'subIssues',
        {
          title: input.title,
          description: null,
          priority: input.severity === 'critical' ? 1 : input.severity === 'high' ? 2 : input.severity === 'medium' ? 3 : 4,
          component: null,
          number,
          identifier,
          kind: tracker.taskTypes.Issue,
          status: project.defaultIssueStatus,
          assignee: null,
          milestone: null,
          dueDate: null,
          estimation: 0,
          reportedTime: 0,
          remainingTime: 0,
          childInfo: [],
          parents: [],
          relations: [],
          subIssues: 0,
          comments: 0,
          reports: 0,
        },
        issueId,
      );

      // Verify the write landed
      const verify = await txClient.findOne(tracker.class.Issue, { _id: issueId });
      if (verify === undefined) {
        throw new Error(`Issue ${identifier} did not persist after creation`);
      }

      // Post the report as a comment
      const messageId = core.generateId();
      const paragraphs = reportText.split('\n').map((line) => ({
        type: 'paragraph' as const,
        content: line.length > 0 ? [{ type: 'text' as const, text: line }] : [],
      }));
      await txClient.addCollection(
        chunter.class.ChatMessage,
        project._id,
        issueId,
        tracker.class.Issue,
        'comments',
        { message: JSON.stringify({ type: 'doc', content: paragraphs }) },
        messageId,
      );

      // Attach screenshot if provided
      if (input.screenshotBase64 && input.screenshotMimeType) {
        try {
          const buffer = Buffer.from(input.screenshotBase64, 'base64');
          const storage = await connectRest(this.hulyUrl, {
            email: this.hulyBotEmail,
            password: this.hulyBotPassword,
            workspace: this.hulyWorkspace,
          });
          const blobId = core.generateId();
          const blob = await storage.put(blobId, buffer, input.screenshotMimeType, buffer.length);
          const attachmentId = core.generateId();
          await txClient.addCollection(
            attachment.class.Attachment,
            project._id,
            issueId,
            tracker.class.Issue,
            'attachments',
            {
              file: blob._id,
              name: `screenshot-${Date.now()}.png`,
              size: buffer.length,
              type: input.screenshotMimeType,
              lastModified: Date.now(),
            },
            attachmentId,
          );
        } catch (attachError) {
          this.logger.warn(`Failed to attach screenshot: ${attachError.message}`);
        }
      }

      const url = `${this.hulyUrl}/workbench/${this.hulyWorkspace}/tracker/${identifier}`;
      this.logger.log(`Bug report created: ${identifier} — ${url}`);
      return { success: true, hulyIssueId: identifier, hulyUrl: url };
    } catch (error) {
      this.logger.error(`Failed to create bug report: ${error.message}`);
      return { success: false, error: `Could not submit bug report: ${error.message}` };
    }
  }
}
