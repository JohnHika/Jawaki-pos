import { Controller, Get, Res, VERSION_NEUTRAL } from '@nestjs/common';
import { Response } from 'express';
import { join } from 'path';

@Controller({ version: VERSION_NEUTRAL })
export class AppController {
  @Get('/')
  serveUI(@Res() res: Response) {
    try {
      const filePath = join(__dirname, '..', 'public', 'index.html');
      return res.sendFile(filePath);
    } catch (error) {
      console.error('Error serving UI:', error);
      return res.status(200).send(`
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>POS System Dashboard</title>
<style>
  body { font-family: Arial, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
  .container { text-align: center; background: white; padding: 40px; border-radius: 10px; box-shadow: 0 10px 25px rgba(0,0,0,0.2); }
  h1 { color: #667eea; margin: 0; }
  p { color: #666; font-size: 16px; }
  button { background: #667eea; color: white; border: none; padding: 12px 30px; border-radius: 5px; cursor: pointer; font-size: 16px; margin-top: 20px; }
  button:hover { background: #764ba2; }
</style>
</head>
<body>
<div class="container">
  <h1>🛍️ POS System</h1>
  <p>Point of Sale Management System</p>
  <p>Backend is running successfully!</p>
  <a href="/api/docs"><button>View API Documentation</button></a>
</div>
</body>
</html>
      `);
    }
  }

  @Get('/health')
  health() {
    return { status: 'ok', message: 'POS System is running', timestamp: new Date() };
  }
}
