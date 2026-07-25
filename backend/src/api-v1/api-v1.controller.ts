import { Controller, Get, Version, Render } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';

@ApiTags('api-v1')
@Controller('api/v1')
export class ApiV1Controller {
  @Get()
  @Version('1')
  @ApiOperation({ summary: 'POS System API v1 - Version documentation' })
  @ApiResponse({
    status: 200,
    description: 'API version documentation',
  })
  getVersionInfo(): object {
    return {
      version: '1.0.0',
      name: 'POS System API',
      description: 'Hybrid Multi-Branch POS System API',
      endpoints: {
        authentication: [
          'POST /api/v1/auth/login',
          'POST /api/v1/auth/login/pin',
          'POST /api/v1/auth/register-company',
          'POST /api/v1/auth/register',
          'POST /api/v1/auth/refresh',
          'POST /api/v1/auth/logout',
          'POST /api/v1/auth/change-password',
          'POST /api/v1/auth/set-pin',
          'GET  /api/v1/auth/profile',
          'GET  /api/v1/auth/users',
        ],
        branches: [
          'GET    /api/v1/branches',
          'POST   /api/v1/branches',
          'GET    /api/v1/branches/:id',
          'PUT    /api/v1/branches/:id',
          'DELETE /api/v1/branches/:id',
          'GET    /api/v1/branches/:id/devices',
          'POST   /api/v1/branches/:id/activate-device',
        ],
        catalog: [
          'GET    /api/v1/catalog/products',
          'POST   /api/v1/catalog/products',
          'GET    /api/v1/catalog/products/:id',
          'PUT    /api/v1/catalog/products/:id',
          'DELETE /api/v1/catalog/products/:id',
          'GET    /api/v1/catalog/categories',
          'POST   /api/v1/catalog/categories',
        ],
        sales: [
          'POST   /api/v1/sales',
          'GET    /api/v1/sales',
          'GET    /api/v1/sales/summary/:branchId/:date',
          'GET    /api/v1/sales/credit',
          'GET    /api/v1/sales/receipt/:receiptNumber',
          'GET    /api/v1/sales/:id',
          'POST   /api/v1/sales/:id/void',
          'POST   /api/v1/sales/refund',
        ],
        inventory: [
          'GET    /api/v1/inventory/stock/:branchId',
          'GET    /api/v1/inventory/stock/product/:productId',
          'POST   /api/v1/inventory/adjust',
          'GET    /api/v1/inventory/movements/:branchId',
          'GET    /api/v1/inventory/low-stock',
          'POST   /api/v1/inventory/transfers',
          'GET    /api/v1/inventory/transfers',
          'GET    /api/v1/inventory/transfers/:id',
          'POST   /api/v1/inventory/transfers/:id/send',
          'POST   /api/v1/inventory/transfers/:id/receive',
        ],
        payments: [
          'POST   /api/v1/payments/mpesa/initiate',
          'GET    /api/v1/payments/mpesa/status/:transactionId',
          'POST   /api/v1/payments/mpesa/callback',
          'GET    /api/v1/payments/methods',
        ],
        reporting: [
          'GET    /api/v1/reports/dashboard',
          'GET    /api/v1/reports/sales/summary',
          'GET    /api/v1/reports/sales/trend',
          'GET    /api/v1/reports/products/top',
          'GET    /api/v1/reports/categories',
          'GET    /api/v1/reports/cashiers',
          'GET    /api/v1/reports/payments',
          'GET    /api/v1/reports/branches',
          'GET    /api/v1/reports/inventory',
          'GET    /api/v1/reports/inventory/movements',
          'GET    /api/v1/reports/profit-loss/:branchId/:date',
          'GET    /api/v1/reports/profit-loss',
        ],
        sync: [
          'POST   /api/v1/sync/events',
          'GET    /api/v1/sync/events',
          'GET    /api/v1/sync/sync-date',
          'POST   /api/v1/sync/finalize',
        ],
      },
      documentation: '/api/docs',
    };
  }

  @Get('*')
  @Version('1')
  @ApiOperation({ summary: '404 - Endpoint not found' })
  @ApiResponse({
    status: 404,
    description: 'The requested endpoint does not exist',
  })
  getNonExistentEndpoint(): object {
    return {
      statusCode: 404,
      message: 'Endpoint not found',
      error: 'Not Found',
    };
  }
}
