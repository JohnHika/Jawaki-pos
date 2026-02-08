import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
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
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { UserRole } from '@prisma/client';

@ApiTags('branches')
@Controller({ path: 'branches', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class BranchesController {
  constructor(private readonly branchesService: BranchesService) {}

  // ==================== TENANT ENDPOINTS ====================

  @Post('tenants')
  @UseGuards(RolesGuard)
  @Roles(UserRole.ADMIN)
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
  @UseGuards(RolesGuard)
  @Roles(UserRole.ADMIN)
  @ApiOperation({ summary: 'Update current tenant' })
  @ApiResponse({ status: 200, description: 'Tenant updated' })
  async updateTenant(@Request() req: any, @Body() dto: UpdateTenantDto) {
    return this.branchesService.updateTenant(req.user.tenantId, dto);
  }

  // ==================== BRANCH ENDPOINTS ====================

  @Post()
  @UseGuards(RolesGuard)
  @Roles(UserRole.ADMIN, UserRole.MANAGER)
  @ApiOperation({ summary: 'Create a new branch' })
  @ApiResponse({ status: 201, description: 'Branch created', type: BranchResponseDto })
  async createBranch(@Request() req: any, @Body() dto: CreateBranchDto) {
    return this.branchesService.createBranch(req.user.tenantId, dto);
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
  @UseGuards(RolesGuard)
  @Roles(UserRole.ADMIN, UserRole.MANAGER)
  @ApiOperation({ summary: 'Update branch' })
  @ApiResponse({ status: 200, description: 'Branch updated', type: BranchResponseDto })
  async updateBranch(
    @Param('id') id: string,
    @Request() req: any,
    @Body() dto: UpdateBranchDto,
  ) {
    return this.branchesService.updateBranch(id, req.user.tenantId, dto);
  }

  @Delete(':id')
  @UseGuards(RolesGuard)
  @Roles(UserRole.ADMIN)
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Delete branch (if no sales history)' })
  @ApiResponse({ status: 204, description: 'Branch deleted' })
  async deleteBranch(@Param('id') id: string, @Request() req: any) {
    await this.branchesService.deleteBranch(id, req.user.tenantId);
  }

  // ==================== DEVICE ENDPOINTS ====================

  @Post(':branchId/devices')
  @UseGuards(RolesGuard)
  @Roles(UserRole.ADMIN, UserRole.MANAGER)
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

  @Patch('devices/:deviceId')
  @UseGuards(RolesGuard)
  @Roles(UserRole.ADMIN, UserRole.MANAGER)
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
  @UseGuards(RolesGuard)
  @Roles(UserRole.ADMIN, UserRole.MANAGER)
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Deactivate device' })
  @ApiResponse({ status: 204, description: 'Device deactivated' })
  async deactivateDevice(@Param('deviceId') deviceId: string, @Request() req: any) {
    await this.branchesService.deactivateDevice(deviceId, req.user.tenantId);
  }
}
