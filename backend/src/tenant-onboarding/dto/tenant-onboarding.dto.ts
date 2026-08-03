import { IsEmail, IsIn, IsNotEmpty, IsString, IsUUID, MaxLength } from 'class-validator';

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

export class AcceptStaffInvitationDto {
  @IsUUID('4')
  challengeId: string;
  @IsString() @IsNotEmpty()
  code: string;
}
