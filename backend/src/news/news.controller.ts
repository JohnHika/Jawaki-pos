import { Controller, Get, HttpCode, HttpStatus, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { IsIn, IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { Type } from 'class-transformer';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';
import { NewsService } from './news.service';

class NewsQueryDto {
  @IsOptional()
  @IsIn(['CUSTOMS_TAX', 'TRADE_IMPORT', 'MONEY_FX', 'COUNTY_LICENSING', 'LOGISTICS', 'MARKET', 'GENERAL'])
  category?: string;

  @IsOptional()
  @IsIn(['HIGH', 'MEDIUM', 'LOW'])
  impact?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  q?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  since?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  limit?: number;
}

@ApiTags('market')
@Controller({ path: 'market/news', version: '1' })
@UseGuards(JwtAuthGuard, PermissionsGuard)
@ApiBearerAuth('JWT-auth')
export class NewsController {
  constructor(private readonly news: NewsService) {}

  @Get()
  @RequirePermissions('news.view')
  @ApiOperation({ summary: 'Business news that can affect a trader (customs, tax, imports, county, fuel, money)' })
  list(@Query() query: NewsQueryDto) {
    return this.news.list(query);
  }

  @Get('digest')
  @RequirePermissions('news.view')
  @ApiOperation({ summary: 'What is urgent this week, plus the latest per topic' })
  digest() {
    return this.news.digest();
  }

  @Get('sources')
  @RequirePermissions('news.view')
  @ApiOperation({ summary: 'Where headlines come from, feed health, and official pages to check' })
  sources() {
    return this.news.sources();
  }

  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: { limit: 2, ttl: 60_000 } })
  @RequirePermissions('news.manage')
  @ApiOperation({ summary: 'Fetch the feeds now instead of waiting for the next scheduled run' })
  refresh() {
    return this.news.refreshAll();
  }
}
