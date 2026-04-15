import {
  IsArray,
  IsString,
  ValidateNested,
  ArrayMinSize,
} from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { CreateBranchDto, UpdateBranchDto } from './branch.dto';

export class BulkCreateBranchItem extends CreateBranchDto {}

export class BulkUpdateBranchItem extends UpdateBranchDto {
  @ApiProperty({ description: 'Branch ID to update' })
  @IsString()
  id: string;
}

export class BulkCreateBranchesDto {
  @ApiProperty({ type: [BulkCreateBranchItem], description: 'Array of branches to create' })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => BulkCreateBranchItem)
  branches: BulkCreateBranchItem[];
}

export class BulkUpdateBranchesDto {
  @ApiProperty({ type: [BulkUpdateBranchItem], description: 'Array of branches to update' })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => BulkUpdateBranchItem)
  branches: BulkUpdateBranchItem[];
}

export class BulkDeleteBranchesDto {
  @ApiProperty({ description: 'Array of branch IDs to delete' })
  @IsArray()
  @ArrayMinSize(1)
  @IsString({ each: true })
  ids: string[];
}
