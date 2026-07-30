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
import { CustomersService } from './customers.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';

@ApiTags('customers')
@Controller({ path: 'customers', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class CustomersController {
  constructor(private readonly customersService: CustomersService) {}

  @Post()
  @ApiOperation({ summary: 'Create a new customer' })
  @ApiResponse({ status: 201, description: 'Customer created' })
  async createCustomer(@Request() req: any, @Body() body: any) {
    return this.customersService.createCustomer(req.user.tenantId, {
      name: body.name,
      phone: body.phone,
      email: body.email,
      address: body.address,
    });
  }

  @Get()
  @ApiOperation({ summary: 'List customers for current tenant' })
  @ApiResponse({ status: 200, description: 'List of active customers' })
  async getCustomers(@Request() req: any) {
    return this.customersService.getCustomers(req.user.tenantId);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get customer by ID' })
  @ApiResponse({ status: 200, description: 'Customer details' })
  async getCustomer(@Param('id') id: string, @Request() req: any) {
    return this.customersService.getCustomer(req.user.tenantId, id);
  }

  @Patch(':id')
  @ApiOperation({ summary: 'Update customer' })
  @ApiResponse({ status: 200, description: 'Customer updated' })
  async updateCustomer(
    @Param('id') id: string,
    @Request() req: any,
    @Body() body: any,
  ) {
    return this.customersService.updateCustomer(req.user.tenantId, id, {
      name: body.name,
      phone: body.phone,
      email: body.email,
      address: body.address,
    });
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Soft-delete a customer (set isActive=false)' })
  @ApiResponse({ status: 204, description: 'Customer deactivated' })
  async deleteCustomer(@Param('id') id: string, @Request() req: any) {
    await this.customersService.deleteCustomer(req.user.tenantId, id);
  }
}