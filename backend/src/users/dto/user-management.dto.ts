import { IsString, IsOptional, IsBoolean, MaxLength } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class AssignRoleDto {
  @ApiProperty({ example: 'role-uuid' })
  @IsString()
  roleId: string;
}

export class CreatePermissionOverrideDto {
  @ApiProperty({ example: 'sales.void' })
  @IsString()
  permissionKey: string;

  @ApiProperty({ description: 'true = extra grant, false = revoke (wins over role grants)' })
  @IsBoolean()
  grant: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(300)
  reason?: string;
}
