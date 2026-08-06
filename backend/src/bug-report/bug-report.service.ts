import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import apiClientPkg from '@hcengineering/api-client';
import trackerPkg from '@hcengineering/tracker';
import chunterPkg from '@hcengineering/chunter';
import attachmentPkg from '@hcengineering/attachment';
import corePkg from '@hcengineering/core';

const apiClient = (apiClientPkg as any).default ?? apiClientPkg;
const { connectRest, connectStorage } = apiClient;
const tracker = ((trackerPkg as any).default ?? trackerPkg) as any;
const chunter = ((chunterPkg as any).default ?? chunterPkg) as any;
const attachment = ((attachmentPkg as any).default ?? attachmentPkg) as any;
const core = corePkg as any;

const CORE_SPACE_SPACE = 'core:space:Space';

export interface BugReportAttachment {
  fileName: string;
  contentType: string;
  buffer: Buffer;
}

export interface CreateBugReportInput {
  title: string;
  description: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  component?: string;
  metadata: {
    appVersion: string;
    deviceOs: string;
    userId: string;
    currentScreen: string;
  };
  attachment?: BugReportAttachment;
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
  private readonly defaultComponent: string;
  private readonly enabled: boolean;

  private txClient: any | undefined;
  private connecting: Promise<any> | undefined;
  private storageClient: any | undefined;
  private connectingStorage: Promise<any> | undefined;
  private botSocialId: string | undefined;

  constructor(private configService: ConfigService) {
    this.hulyUrl = this.configService.get<string>('HULY_URL', 'https://tickets.arche-axon.xyz');
    this.hulyWorkspace = this.configService.get<string>('HULY_WORKSPACE', 'archeaxonintelligence');
    this.hulyBotEmail = this.configService.get<string>('HULY_BOT_EMAIL', '');
    this.hulyBotPassword = this.configService.get<string>('HULY_BOT_PASSWORD', '');
    this.projectIdentifier = this.configService.get<string>('HULY_BUG_PROJECT', 'BUG');
    this.defaultComponent = this.configService.get<string>('HULY_DEFAULT_COMPONENT', 'Axon');
    this.enabled = !!(this.hulyBotEmail && this.hulyBotPassword);
    if (!this.enabled) {
      this.logger.warn('HULY_BOT_EMAIL/PASSWORD not set — bug reports will be logged but not sent to Huly');
    }
  }

  private async getHulyClient(): Promise<any> {
    if (this.txClient !== undefined) return this.txClient;
    if (this.connecting !== undefined) return this.connecting;
    this.connecting = this.buildClient()
      .then((c) => {
        this.txClient = c;
        this.connecting = undefined;
        return c;
      })
      .catch((err) => {
        this.connecting = undefined;
        throw err;
      });
    return this.connecting;
  }

  private async buildClient(): Promise<any> {
    const restClient = await connectRest(this.hulyUrl, {
      email: this.hulyBotEmail,
      password: this.hulyBotPassword,
      workspace: this.hulyWorkspace,
    });
    const account = await restClient.getAccount();
    this.botSocialId = account.primarySocialId;
    const { hierarchy } = await restClient.getModel();
    restClient.getHierarchy = () => hierarchy;
    return new core.TxOperations(restClient, account.primarySocialId);
  }

  private async getStorageClient(): Promise<any> {
    if (this.storageClient !== undefined) return this.storageClient;
    if (this.connectingStorage !== undefined) return this.connectingStorage;
    this.connectingStorage = connectStorage(this.hulyUrl, {
      email: this.hulyBotEmail,
      password: this.hulyBotPassword,
      workspace: this.hulyWorkspace,
    })
      .then((c: any) => {
        this.storageClient = c;
        this.connectingStorage = undefined;
        return c;
      })
      .catch((err: unknown) => {
        this.connectingStorage = undefined;
        throw err;
      });
    return this.connectingStorage;
  }

  private async resolveProject(client: any) {
    const project = await client.findOne(tracker.class.Project, { identifier: this.projectIdentifier });
    if (project === undefined) {
      throw new Error(`Huly project "${this.projectIdentifier}" not found`);
    }
    return project;
  }

  private async resolveOrCreateComponent(client: any, project: any, label: string) {
    let component = await client.findOne(tracker.class.Component, { space: project._id, label });
    if (component === undefined) {
      const id = await client.createDoc(tracker.class.Component, project._id, {
        label,
        description: '',
        lead: null,
        attachments: 0,
      });
      component = await client.findOne(tracker.class.Component, { _id: id });
    }
    return component;
  }

  async createBugReport(input: CreateBugReportInput): Promise<CreateBugReportResult> {
    if (!this.enabled) {
      this.logger.log(`Bug report (Huly disabled): ${input.title}`);
      return { success: false, error: 'Bug reporting service is not configured. Please contact support.' };
    }

    try {
      const client = await this.getHulyClient();
      const project = await this.resolveProject(client);
      const componentLabel = input.component?.trim() || this.defaultComponent;
      const component = componentLabel ? await this.resolveOrCreateComponent(client, project, componentLabel) : undefined;

      await client.updateDoc(
        tracker.class.Project,
        CORE_SPACE_SPACE,
        project._id,
        { $inc: { sequence: 1 } },
        true,
      );
      const updated = await client.findOne(tracker.class.Project, { _id: project._id });
      const number: number = updated?.sequence ?? 1;
      const identifier = `${this.projectIdentifier}-${number}`;
      const issueId = core.generateId();

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
        `- **Component:** ${componentLabel}`,
      ].join('\n');

      await client.addCollection(
        tracker.class.Issue,
        project._id,
        tracker.ids.NoParent,
        tracker.class.Issue,
        'subIssues',
        {
          title: input.title,
          description: null,
          priority: this.severityToPriority(input.severity),
          component: component?._id ?? null,
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

      const verify = await client.findOne(tracker.class.Issue, { _id: issueId });
      if (verify === undefined) {
        throw new Error(`Issue ${identifier} did not persist after creation`);
      }

      await this.postComment(client, project._id, issueId, reportText);

      if (input.attachment) {
        await this.attachFile(client, project._id, issueId, input.attachment);
      }

      const url = `${this.hulyUrl}/workbench/${this.hulyWorkspace}/tracker/${identifier}`;
      this.logger.log(`Bug report created: ${identifier} — ${url}`);
      return { success: true, hulyIssueId: identifier, hulyUrl: url };
    } catch (error) {
      this.logger.error(`Failed to create bug report: ${error.message}`);
      return { success: false, error: `Could not submit bug report: ${error.message}` };
    }
  }

  private severityToPriority(severity: string): number {
    switch (severity) {
      case 'critical':
        return 1;
      case 'high':
        return 2;
      case 'medium':
        return 3;
      default:
        return 4;
    }
  }

  private async postComment(client: any, projectId: string, targetId: string, text: string) {
    const messageId = core.generateId();
    const paragraphs = text.split('\n').map((line) => ({
      type: 'paragraph' as const,
      content: line.length > 0 ? [{ type: 'text' as const, text: line }] : [],
    }));
    await client.addCollection(
      chunter.class.ChatMessage,
      projectId,
      targetId,
      tracker.class.Issue,
      'comments',
      { message: JSON.stringify({ type: 'doc', content: paragraphs }) },
      messageId,
    );
  }

  private async attachFile(client: any, projectId: string, targetId: string, attachmentInput: BugReportAttachment) {
    const storage = await this.getStorageClient();
    const blobId = core.generateId();
    const blob = await storage.put(blobId, attachmentInput.buffer, attachmentInput.contentType, attachmentInput.buffer.length);

    const attachmentId = core.generateId();
    await client.addCollection(
      attachment.class.Attachment,
      projectId,
      targetId,
      tracker.class.Issue,
      'attachments',
      {
        file: blob._id,
        name: attachmentInput.fileName,
        size: attachmentInput.buffer.length,
        type: attachmentInput.contentType,
        lastModified: Date.now(),
      },
      attachmentId,
    );
  }
}
