import { IsIn, IsString, MaxLength } from 'class-validator';
import { POLICY_VERSIONS } from '../policy-versions';

export class AcceptPolicyDto {
  @IsString()
  @IsIn(Object.keys(POLICY_VERSIONS))
  policyType!: string;

  @IsString()
  @MaxLength(40)
  policyVersion!: string;
}
