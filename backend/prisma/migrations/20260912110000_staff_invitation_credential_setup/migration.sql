ALTER TABLE "tenant_staff_invitations"
  ADD COLUMN "credentialSetupTokenHash" TEXT,
  ADD COLUMN "credentialSetupExpiresAt" TIMESTAMP(3);

CREATE UNIQUE INDEX "tenant_staff_invitations_credentialSetupTokenHash_key"
  ON "tenant_staff_invitations"("credentialSetupTokenHash");
