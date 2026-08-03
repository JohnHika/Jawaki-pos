-- Verified workspace identity, durable OTPs, activation attempts, and onboarding.
ALTER TABLE "users"
  ALTER COLUMN "passwordHash" DROP NOT NULL,
  ADD COLUMN "identityProvider" TEXT,
  ADD COLUMN "identityVerifiedAt" TIMESTAMP(3);

CREATE TABLE "email_otp_challenges" (
  "id" TEXT NOT NULL,
  "purpose" TEXT NOT NULL,
  "email" TEXT NOT NULL,
  "tenantId" TEXT,
  "codeHash" TEXT NOT NULL,
  "attempts" INTEGER NOT NULL DEFAULT 0,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "resendAvailableAt" TIMESTAMP(3) NOT NULL,
  "sentAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "consumedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "email_otp_challenges_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "tenant_activation_attempts" (
  "id" TEXT NOT NULL,
  "tenantId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "email" TEXT NOT NULL,
  "idempotencyKey" TEXT NOT NULL,
  "reference" TEXT NOT NULL,
  "provider" TEXT NOT NULL,
  "amount" DECIMAL(12,2) NOT NULL,
  "authorizationUrl" TEXT,
  "status" TEXT NOT NULL DEFAULT 'INITIALIZED',
  "providerResponse" JSONB,
  "verifiedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "tenant_activation_attempts_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "tenant_onboarding" (
  "id" TEXT NOT NULL,
  "tenantId" TEXT NOT NULL,
  "ownerUserId" TEXT NOT NULL,
  "state" TEXT NOT NULL DEFAULT 'IN_PROGRESS',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "tenant_onboarding_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "tenant_onboarding_steps" (
  "id" TEXT NOT NULL,
  "onboardingId" TEXT NOT NULL,
  "key" TEXT NOT NULL,
  "position" INTEGER NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'PENDING',
  "completedAt" TIMESTAMP(3),
  "deferredAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "tenant_onboarding_steps_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "tenant_staff_invitations" (
  "id" TEXT NOT NULL,
  "tenantId" TEXT NOT NULL,
  "email" TEXT NOT NULL,
  "firstName" TEXT NOT NULL,
  "lastName" TEXT NOT NULL,
  "roleId" TEXT NOT NULL,
  "branchId" TEXT NOT NULL,
  "createdById" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'PENDING',
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "acceptedAt" TIMESTAMP(3),
  "challengeId" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "tenant_staff_invitations_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "tenant_activation_attempts_reference_key" ON "tenant_activation_attempts"("reference");
CREATE UNIQUE INDEX "tenant_activation_attempts_tenantId_idempotencyKey_key" ON "tenant_activation_attempts"("tenantId", "idempotencyKey");
CREATE INDEX "tenant_activation_attempts_tenantId_createdAt_idx" ON "tenant_activation_attempts"("tenantId", "createdAt");
CREATE INDEX "email_otp_challenges_email_purpose_tenantId_createdAt_idx" ON "email_otp_challenges"("email", "purpose", "tenantId", "createdAt");
CREATE INDEX "email_otp_challenges_expiresAt_idx" ON "email_otp_challenges"("expiresAt");
CREATE UNIQUE INDEX "tenant_onboarding_tenantId_key" ON "tenant_onboarding"("tenantId");
CREATE INDEX "tenant_onboarding_ownerUserId_idx" ON "tenant_onboarding"("ownerUserId");
CREATE UNIQUE INDEX "tenant_onboarding_steps_onboardingId_key_key" ON "tenant_onboarding_steps"("onboardingId", "key");
CREATE UNIQUE INDEX "tenant_onboarding_steps_onboardingId_position_key" ON "tenant_onboarding_steps"("onboardingId", "position");
CREATE UNIQUE INDEX "tenant_staff_invitations_challengeId_key" ON "tenant_staff_invitations"("challengeId");
CREATE INDEX "tenant_staff_invitations_tenantId_email_status_idx" ON "tenant_staff_invitations"("tenantId", "email", "status");

ALTER TABLE "email_otp_challenges" ADD CONSTRAINT "email_otp_challenges_tenantId_fkey"
  FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "tenant_activation_attempts" ADD CONSTRAINT "tenant_activation_attempts_tenantId_fkey"
  FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "tenant_activation_attempts" ADD CONSTRAINT "tenant_activation_attempts_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "tenant_onboarding" ADD CONSTRAINT "tenant_onboarding_tenantId_fkey"
  FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "tenant_onboarding" ADD CONSTRAINT "tenant_onboarding_ownerUserId_fkey"
  FOREIGN KEY ("ownerUserId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "tenant_onboarding_steps" ADD CONSTRAINT "tenant_onboarding_steps_onboardingId_fkey"
  FOREIGN KEY ("onboardingId") REFERENCES "tenant_onboarding"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "tenant_staff_invitations" ADD CONSTRAINT "tenant_staff_invitations_tenantId_fkey"
  FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "tenant_staff_invitations" ADD CONSTRAINT "tenant_staff_invitations_roleId_fkey"
  FOREIGN KEY ("roleId") REFERENCES "roles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "tenant_staff_invitations" ADD CONSTRAINT "tenant_staff_invitations_branchId_fkey"
  FOREIGN KEY ("branchId") REFERENCES "branches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "tenant_staff_invitations" ADD CONSTRAINT "tenant_staff_invitations_createdById_fkey"
  FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "tenant_staff_invitations" ADD CONSTRAINT "tenant_staff_invitations_challengeId_fkey"
  FOREIGN KEY ("challengeId") REFERENCES "email_otp_challenges"("id") ON DELETE SET NULL ON UPDATE CASCADE;
