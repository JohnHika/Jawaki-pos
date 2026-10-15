import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PartnersService } from './partners.service';
import { CreatePartnerRequestDto, SendPartnerMessageDto } from './dto/partners.dto';

@ApiTags('partners')
@Controller({ path: 'partners', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class PartnersController {
  constructor(private readonly partnersService: PartnersService) {}

  @Get()
  @ApiOperation({ summary: 'List trade partners and pending requests' })
  async list(@Request() req: any) {
    return { success: true, data: await this.partnersService.list(req.user) };
  }

  @Post('requests')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Send a trade partner request by company code' })
  async createRequest(@Request() req: any, @Body() dto: CreatePartnerRequestDto) {
    return { success: true, data: await this.partnersService.createRequest(req.user, dto) };
  }

  @Post(':id/accept')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Accept an incoming partner request' })
  async accept(@Request() req: any, @Param('id') id: string) {
    return { success: true, data: await this.partnersService.accept(req.user, id) };
  }

  @Post(':id/decline')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Decline an incoming partner request' })
  async decline(@Request() req: any, @Param('id') id: string) {
    return { success: true, data: await this.partnersService.decline(req.user, id) };
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Remove a partner or withdraw a pending request' })
  async remove(@Request() req: any, @Param('id') id: string) {
    return { success: true, data: await this.partnersService.remove(req.user, id) };
  }

  @Get(':id/messages')
  @ApiOperation({ summary: 'List chat messages with a partner (marks theirs as read)' })
  async messages(
    @Request() req: any,
    @Param('id') id: string,
    @Query('after') after?: string,
    @Query('limit') limit?: string,
  ) {
    return {
      success: true,
      data: await this.partnersService.getMessages(
        req.user,
        id,
        after,
        limit !== undefined && limit !== '' ? Number(limit) : undefined,
      ),
    };
  }

  @Post(':id/messages')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Send a chat message to a partner' })
  async sendMessage(
    @Request() req: any,
    @Param('id') id: string,
    @Body() dto: SendPartnerMessageDto,
  ) {
    return { success: true, data: await this.partnersService.sendMessage(req.user, id, dto) };
  }
}
