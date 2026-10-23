import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Put,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { StatementsService } from './statements.service';
import {
  ClaimsQueryDto,
  CreateStatementLinkDto,
  DecideClaimDto,
  LinksQueryDto,
  StatementTargetDto,
  UpdateStatementSettingsDto,
} from './dto/statements.dto';

function exactlyOne(target: StatementTargetDto) {
  if (!target.customerId === !target.debtorId) {
    throw new BadRequestException('Name either a customer or a shop');
  }
}

@ApiTags('statements')
@Controller({ path: 'statements', version: '1' })
@UseGuards(JwtAuthGuard, PermissionsGuard)
@ApiBearerAuth('JWT-auth')
export class StatementsController {
  constructor(private readonly statements: StatementsService) {}

  @Get('settings')
  @RequirePermissions('statements.share')
  @ApiOperation({ summary: 'How customers pay you, as shown on statements' })
  getSettings(@CurrentUser('tenantId') tenantId: string) {
    return this.statements.getSettings(tenantId);
  }

  @Put('settings')
  @RequirePermissions('statements.manage')
  @ApiOperation({ summary: 'Set the payment details and phone shown on statements' })
  updateSettings(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: UpdateStatementSettingsDto,
  ) {
    return this.statements.updateSettings(userId, tenantId, dto);
  }

  @Get('preview')
  @RequirePermissions('statements.share')
  @ApiOperation({ summary: 'What a customer or shop owes right now, as the statement will show it' })
  preview(@CurrentUser('tenantId') tenantId: string, @Query() query: StatementTargetDto) {
    exactlyOne(query);
    return this.statements.preview(tenantId, query);
  }

  @Post('links')
  @RequirePermissions('statements.share')
  @ApiOperation({ summary: 'Make a shareable statement link for a customer or shop' })
  createLink(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Body() dto: CreateStatementLinkDto,
  ) {
    return this.statements.createLink(userId, tenantId, dto);
  }

  @Get('links')
  @RequirePermissions('statements.share')
  @ApiOperation({ summary: 'Links already sent to a customer or shop, and whether they were opened' })
  listLinks(@CurrentUser('tenantId') tenantId: string, @Query() query: LinksQueryDto) {
    return this.statements.listLinks(tenantId, query);
  }

  @Post('links/:id/revoke')
  @RequirePermissions('statements.share')
  @ApiOperation({ summary: 'Stop a link from working' })
  revoke(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.statements.revoke(userId, tenantId, id);
  }

  @Get('claims')
  @RequirePermissions('statements.share')
  @ApiOperation({ summary: 'Customers saying "I have paid" or "I will pay on"' })
  claims(@CurrentUser('tenantId') tenantId: string, @Query() query: ClaimsQueryDto) {
    return this.statements.listClaims(tenantId, query);
  }

  @Post('claims/:id/decide')
  @RequirePermissions('statements.share', 'finance.manage_receivables')
  @ApiOperation({ summary: 'Confirm (records the payment) or reject a customer reply' })
  decide(
    @CurrentUser('id') userId: string,
    @CurrentUser('tenantId') tenantId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: DecideClaimDto,
  ) {
    return this.statements.decideClaim(userId, tenantId, id, dto);
  }
}
