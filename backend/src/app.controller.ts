import { Controller, Get, VERSION_NEUTRAL } from '@nestjs/common';

@Controller({ version: VERSION_NEUTRAL })
export class AppController {
  @Get('/')
  root() {
    return {
      status: 'ok',
      name: 'Arche Axon POS API',
      message: 'Backend is running successfully',
      docs: '/api/docs',
      health: '/health',
      timestamp: new Date(),
    };
  }

  @Get('/health')
  health() {
    return {
      status: 'ok',
      message: 'POS System is running',
      timestamp: new Date(),
    };
  }
}
