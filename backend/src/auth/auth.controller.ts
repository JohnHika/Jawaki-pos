import {
  Controller,
  Post,
  Get,
  Body,
  UseGuards,
  Request,
  Query,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
} from '@nestjs/swagger';
import { AuthService } from './auth.service';
import {
  LoginDto,
  PinLoginDto,
  RegisterCompanyDto,
  RegisterDto,
  RefreshTokenDto,
  LogoutDto,
  ChangePasswordDto,
  SetPinDto,
  AuthResponseDto,
  CompanyInfoResponseDto,
} from './dto/auth.dto';
import { JwtAuthGuard } from './guards/jwt-auth.guard';
import { RolesGuard } from './guards/roles.guard';
import { Roles } from './decorators/roles.decorator';
import { UserRole } from '@prisma/client';

@ApiTags('auth')
@Controller({ path: 'auth', version: '1' })
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('login')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Login with email and password' })
  @ApiResponse({ status: 200, description: 'Login successful', type: AuthResponseDto })
  @ApiResponse({ status: 401, description: 'Invalid credentials' })
  async login(@Body() loginDto: LoginDto): Promise<AuthResponseDto> {
    return this.authService.login(loginDto);
  }

  @Post('register-company')
  @ApiOperation({ summary: 'Create a new company, first shop, and owner admin' })
  @ApiResponse({ status: 201, description: 'Company registered', type: AuthResponseDto })
  @ApiResponse({ status: 409, description: 'Company already exists' })
  async registerCompany(@Body() dto: RegisterCompanyDto): Promise<AuthResponseDto> {
    return this.authService.registerCompany(dto);
  }

  @Get('company-info')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Get company name and logo by tenant slug (public)' })
  @ApiResponse({ status: 200, description: 'Company info', type: CompanyInfoResponseDto })
  @ApiResponse({ status: 404, description: 'Company not found' })
  async getCompanyInfo(@Query('slug') slug: string): Promise<CompanyInfoResponseDto> {
    return this.authService.getCompanyInfo(slug);
  }

  @Post('login/pin')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Quick login with PIN (for POS terminals)' })
  @ApiResponse({ status: 200, description: 'Login successful', type: AuthResponseDto })
  @ApiResponse({ status: 401, description: 'Invalid PIN' })
  async loginWithPin(@Body() pinLoginDto: PinLoginDto): Promise<AuthResponseDto> {
    return this.authService.loginWithPin(pinLoginDto);
  }

  @Post('pin-login')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Quick login with PIN (legacy path alias)' })
  @ApiResponse({ status: 200, description: 'Login successful', type: AuthResponseDto })
  @ApiResponse({ status: 401, description: 'Invalid PIN' })
  async loginWithPinLegacy(@Body() pinLoginDto: PinLoginDto): Promise<AuthResponseDto> {
    return this.authService.loginWithPin(pinLoginDto);
  }

  @Post('register')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN, UserRole.MANAGER)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Register a new user (Admin/Manager only)' })
  @ApiResponse({ status: 201, description: 'User registered', type: AuthResponseDto })
  @ApiResponse({ status: 409, description: 'User already exists' })
  async register(@Body() registerDto: RegisterDto): Promise<AuthResponseDto> {
    return this.authService.register(registerDto);
  }

  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Refresh access token' })
  @ApiResponse({ status: 200, description: 'Token refreshed', type: AuthResponseDto })
  @ApiResponse({ status: 401, description: 'Invalid refresh token' })
  async refreshToken(@Body() refreshTokenDto: RefreshTokenDto): Promise<AuthResponseDto> {
    return this.authService.refreshToken(refreshTokenDto);
  }

  @Post('logout')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Logout and invalidate tokens' })
  @ApiResponse({ status: 204, description: 'Logged out successfully' })
  async logout(@Request() req: any, @Body() logoutDto: LogoutDto): Promise<void> {
    await this.authService.logout(req.user.sub, logoutDto);
  }

  @Post('change-password')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Change password' })
  @ApiResponse({ status: 204, description: 'Password changed' })
  @ApiResponse({ status: 401, description: 'Current password incorrect' })
  async changePassword(
    @Request() req: any,
    @Body() changePasswordDto: ChangePasswordDto,
  ): Promise<void> {
    await this.authService.changePassword(req.user.sub, changePasswordDto);
  }

  @Post('set-pin')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Set or update PIN for quick login' })
  @ApiResponse({ status: 204, description: 'PIN set successfully' })
  async setPin(@Request() req: any, @Body() setPinDto: SetPinDto): Promise<void> {
    await this.authService.setPin(req.user.sub, setPinDto);
  }

  @Get('profile')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Get current user profile' })
  @ApiResponse({ status: 200, description: 'User profile' })
  async getProfile(@Request() req: any) {
    return this.authService.getProfile(req.user.sub);
  }

  @Get('users')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN, UserRole.MANAGER)
  @ApiBearerAuth('JWT-auth')
  @ApiOperation({ summary: 'Get users for the current company only' })
  @ApiResponse({ status: 200, description: 'Company users' })
  async getTenantUsers(@Request() req: any) {
    return this.authService.getTenantUsers(req.user.tenantId);
  }
}
