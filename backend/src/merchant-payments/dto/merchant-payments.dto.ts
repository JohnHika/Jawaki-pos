import { Type } from 'class-transformer';
import { IsBoolean, IsEmail, IsIn, IsNotEmpty, IsNumber, IsString, IsUUID, Matches, Max, MaxLength, Min, ValidateNested } from 'class-validator';
import { CreateSaleDto } from '../../sales/dto/sales.dto';

export class ConfigureMerchantPayoutDto {
  @IsString() @IsNotEmpty() @MaxLength(30)
  bankCode!: string;

  @IsString() @Matches(/^\d{6,20}$/, { message: 'Enter a valid bank account number' })
  accountNumber!: string;

  @IsBoolean()
  confirmAccountOwnership!: boolean;
}

export class StartMerchantMpesaDto {
  @IsUUID('4')
  requestId!: string;

  @IsString() @Matches(/^(?:\+?254|0)?(?:7|1)\d{8}$/, {
    message: 'Enter a valid Kenyan M-Pesa phone number',
  })
  phoneNumber!: string;

  @IsEmail() @MaxLength(254)
  customerEmail!: string;

  @ValidateNested()
  @Type(() => CreateSaleDto)
  sale!: CreateSaleDto;
}

export class StartMerchantReceivableMpesaDto {
  @IsUUID('4')
  requestId!: string;

  @IsIn(['retail', 'peer'])
  receivableType!: 'retail' | 'peer';

  @IsUUID('4')
  receivableId!: string;

  @IsUUID('4')
  branchId!: string;

  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(3)
  @Max(9_999_999)
  amount!: number;

  @IsString() @Matches(/^(?:\+?254|0)?(?:7|1)\d{8}$/)
  phoneNumber!: string;

  @IsEmail() @MaxLength(254)
  customerEmail!: string;
}
