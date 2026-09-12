import {
  IsEmail,
  IsIn,
  IsNotEmpty,
  IsString,
  IsUUID,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';

export class UpdateOnboardingStepDto {
  @IsIn(['PENDING', 'DEFERRED', 'COMPLETED'])
  status: 'PENDING' | 'DEFERRED' | 'COMPLETED';
}

export class CreateStaffInvitationDto {
  @IsEmail()
  email: string;
  @IsString() @IsNotEmpty() @MaxLength(100)
  firstName: string;
  @IsString() @IsNotEmpty() @MaxLength(100)
  lastName: string;
  @IsUUID('4')
  roleId: string;
  @IsUUID('4')
  branchId: string;
}

export class CompleteStaffInvitationCredentialsDto {
  @IsString() @IsNotEmpty() @MaxLength(128)
  setupToken: string;

  @IsString() @MinLength(8) @MaxLength(128)
  @Matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/, {
    message: 'Password must contain an uppercase letter, lowercase letter, and number',
  })
  password: string;

  @IsString() @Matches(/^\d{4,6}$/, { message: 'PIN must contain 4–6 digits' })
  pin: string;
}

export class AcceptStaffInvitationDto {
  @IsUUID('4')
  challengeId: string;
  @IsString() @IsNotEmpty()
  code: string;
}
