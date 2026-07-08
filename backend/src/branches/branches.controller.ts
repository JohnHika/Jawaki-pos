import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  Query,
  UseGuards,
  Request,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiQuery,
} from '@nestjs/swagger';
import { BranchesService } from './branches.service';
import {
  CreateTenantDto,
  UpdateTenantDto,
  CreateBranchDto,
  UpdateBranchDto,
  RegisterDeviceDto,
  UpdateDeviceDto,
  BranchResponseDto,
  DeviceResponseDto,
} from './dto/branch.dto';
import {
  BulkCreateBranchesDto,
  BulkUpdateBranchesDto,
  BulkDeleteBranchesDto,
} from './dto/bulk-branch.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';

@ApiTags('branches')
@Controller({ path: 'branches', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class BranchesController {
  constructor(private readonly branchesService: BranchesService) {}

  // ==================== TENANT ENDPOINTS ====================

  @Post('tenants')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('branches.tenant.create')
  @ApiOperation({ summary: 'Create a new tenant (Super Admin only)' })
  @ApiResponse({ status: 201, description: 'Tenant created' })
  async createTenant(@Body() dto: CreateTenantDto) {
    return this.branchesService.createTenant(dto);
  }

  @Get('tenants/current')
  @ApiOperation({ summary: 'Get current tenant info' })
  @ApiResponse({ status: 200, description: 'Tenant details' })
  async getCurrentTenant(@Request() req: any) {
    return this.branchesService.getTenant(req.user.tenantId);
  }

  @Patch('tenants/current')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('branches.tenant.update')
  @ApiOperation({ summary: 'Update current tenant' })
  @ApiResponse({ status: 200, description: 'Tenant updated' })
  async updateTenant(@Request() req: any, @Body() dto: UpdateTenantDto) {
    return this.branchesService.updateTenant(req.user.tenantId, dto);
  }

  // ==================== BRANCH ENDPOINTS ====================

  @Post()
  @UseGuards(PermissionsGuard)
  @RequirePermissions('branches.create')
  @ApiOperation({ summary: 'Create a new branch' })
  @ApiResponse({ status: 201, description: 'Branch created', type: BranchResponseDto })
  async createBranch(@Request() req: any, @Body() dto: CreateBranchDto) {
    return this.branchesService.createBranch(req.user.tenantId, dto, req.user.sub);
  }

  @Get()
  @ApiOperation({ summary: 'Get all branches for current tenant' })
  @ApiResponse({ status: 200, description: 'List of branches', type: [BranchResponseDto] })
  async getBranches(@Request() req: any) {
    return this.branchesService.getBranches(req.user.tenantId);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get branch by ID' })
  @ApiResponse({ status: 200, description: 'Branch details', type: BranchResponseDto })
  async getBranch(@Param('id') id: string, @Request() req: any) {
    return this.branchesService.getBranch(id, req.user.tenantId);
  }

  @Patch(':id')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('branches.update')
  @ApiOperation({ summary: 'Update branch' })
  @ApiResponse({ status: 200, description: 'Branch updated', type: BranchResponseDto })
  async updateBranch(
    @Param('id') id: string,
    @Request() req: any,
    @Body() dto: UpdateBranchDto,
  ) {
    return this.branchesService.updateBranch(id, req.user.tenantId, dto, req.user.sub);
  }

  @Delete(':id')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('branches.delete')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Delete branch (if no sales history)' })
  @ApiResponse({ status: 204, description: 'Branch deleted' })
  async deleteBranch(@Param('id') id: string, @Request() req: any) {
    await this.branchesService.deleteBranch(id, req.user.tenantId, req.user.sub);
  }

  // ==================== BULK BRANCH ENDPOINTS ====================

  @Post('bulk')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('branches.bulk')
  @ApiOperation({ summary: 'Bulk create branches' })
  @ApiResponse({ status: 201, description: 'Branches created', type: [BranchResponseDto] })
  async bulkCreateBranches(@Request() req: any, @Body() dto: BulkCreateBranchesDto) {
    return this.branchesService.bulkCreateBranches(req.user.tenantId, dto.branches);
  }

  @Patch('bulk')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('branches.bulk')
  @ApiOperation({ summary: 'Bulk update branches' })
  @ApiResponse({ status: 200, description: 'Branches updated', type: [BranchResponseDto] })
  async bulkUpdateBranches(@Request() req: any, @Body() dto: BulkUpdateBranchesDto) {
    return this.branchesService.bulkUpdateBranches(req.user.tenantId, dto.branches);
  }

  @Delete('bulk')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('branches.bulk')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Bulk delete branches (if no sales)' })
  @ApiResponse({ status: 204, description: 'Branches deleted' })
  async bulkDeleteBranches(@Request() req: any, @Body() dto: BulkDeleteBranchesDto) {
    await this.branchesService.bulkDeleteBranches(req.user.tenantId, dto.ids);
  }

  // ==================== DEVICE ENDPOINTS ====================

  @Post(':branchId/devices')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('devices.create')
  @ApiOperation({ summary: 'Register a new device to a branch' })
  @ApiResponse({ status: 201, description: 'Device registered', type: DeviceResponseDto })
  async registerDevice(@Request() req: any, @Body() dto: RegisterDeviceDto) {
    return this.branchesService.registerDevice(req.user.tenantId, dto);
  }

  @Get(':branchId/devices')
  @ApiOperation({ summary: 'Get all devices for a branch' })
  @ApiResponse({ status: 200, description: 'List of devices', type: [DeviceResponseDto] })
  async getDevices(@Param('branchId') branchId: string, @Request() req: any) {
    return this.branchesService.getDevices(branchId, req.user.tenantId);
  }

  @Get('devices/:deviceId')
  @ApiOperation({ summary: 'Get device by ID' })
  @ApiResponse({ status: 200, description: 'Device details', type: DeviceResponseDto })
  async getDevice(@Param('deviceId') deviceId: string) {
    return this.branchesService.getDevice(deviceId);
  }

  @Get(':branchId/devices/outdated')
  @ApiOperation({ summary: 'Get outdated devices for a branch' })
  @ApiResponse({ status: 200, description: 'List of outdated devices', type: [DeviceResponseDto] })
  @ApiQuery({
    name: 'minVersion',
    required: true,
    description: 'Minimum required app version (e.g., "1.0.4+2006")',
    example: '1.0.4+2006',
  })
  async getOutdatedDevices(
    @Param('branchId') branchId: string,
    @Query('minVersion') minVersion: string,
    @Request() req: any,
  ) {
    return this.branchesService.getOutdatedDevices(branchId, req.user.tenantId, minVersion);
  }

  @Patch('devices/:deviceId')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('devices.update')
  @ApiOperation({ summary: 'Update device' })
  @ApiResponse({ status: 200, description: 'Device updated', type: DeviceResponseDto })
  async updateDevice(
    @Param('deviceId') deviceId: string,
    @Request() req: any,
    @Body() dto: UpdateDeviceDto,
  ) {
    return this.branchesService.updateDevice(deviceId, req.user.tenantId, dto);
  }

  @Delete('devices/:deviceId')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('devices.delete')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Deactivate device' })
  @ApiResponse({ status: 204, description: 'Device deactivated' })
  async deactivateDevice(@Param('deviceId') deviceId: string, @Request() req: any) {
    await this.branchesService.deactivateDevice(deviceId, req.user.tenantId);
  }
}
