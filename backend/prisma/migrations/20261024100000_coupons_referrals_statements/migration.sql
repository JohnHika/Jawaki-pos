-- CreateEnum
CREATE TYPE "CouponKind" AS ENUM ('PERCENT', 'FIXED');

-- CreateTable
CREATE TABLE "coupons" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT,
    "kind" "CouponKind" NOT NULL,
    "value" DECIMAL(12,2) NOT NULL,
    "maxDiscount" DECIMAL(12,2),
    "minSpend" DECIMAL(12,2),
    "startsAt" TIMESTAMP(3),
    "expiresAt" TIMESTAMP(3),
    "usageLimit" INTEGER,
    "perCustomerLimit" INTEGER,
    "customerId" TEXT,
    "productIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "usedCount" INTEGER NOT NULL DEFAULT 0,
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "coupons_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "coupon_redemptions" (
    "id" TEXT NOT NULL,
    "couponId" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "branchId" TEXT NOT NULL,
    "saleId" TEXT NOT NULL,
    "customerId" TEXT,
    "userId" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "coupon_redemptions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "promo_codes" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "description" TEXT,
    "freeDays" INTEGER NOT NULL,
    "maxRedemptions" INTEGER,
    "redeemedCount" INTEGER NOT NULL DEFAULT 0,
    "expiresAt" TIMESTAMP(3),
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "promo_codes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "promo_redemptions" (
    "id" TEXT NOT NULL,
    "promoId" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "daysGranted" INTEGER NOT NULL,
    "appliedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "promo_redemptions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "referral_codes" (
    "tenantId" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "referral_codes_pkey" PRIMARY KEY ("tenantId")
);

-- CreateTable
CREATE TABLE "referrals" (
    "id" TEXT NOT NULL,
    "referrerTenantId" TEXT NOT NULL,
    "referredTenantId" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "referredDays" INTEGER,
    "referrerDays" INTEGER,
    "rewardedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "referrals_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "statement_links" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "token" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "customerId" TEXT,
    "debtorId" TEXT,
    "message" TEXT,
    "createdById" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "firstViewedAt" TIMESTAMP(3),
    "lastViewedAt" TIMESTAMP(3),
    "viewCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "statement_links_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "statement_claims" (
    "id" TEXT NOT NULL,
    "linkId" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "amount" DECIMAL(12,2),
    "mpesaCode" TEXT,
    "promisedFor" TIMESTAMP(3),
    "payerName" TEXT,
    "note" TEXT,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "decidedAt" TIMESTAMP(3),
    "decidedById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "statement_claims_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "mpesa_entries" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "senderName" TEXT,
    "senderPhone" TEXT,
    "paidAt" TIMESTAMP(3),
    "status" TEXT NOT NULL DEFAULT 'UNMATCHED',
    "matchedCustomerId" TEXT,
    "matchedDebtorId" TEXT,
    "createdById" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "mpesa_entries_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "coupons_tenantId_isActive_idx" ON "coupons"("tenantId", "isActive");

-- CreateIndex
CREATE UNIQUE INDEX "coupons_tenantId_code_key" ON "coupons"("tenantId", "code");

-- CreateIndex
CREATE UNIQUE INDEX "coupon_redemptions_saleId_key" ON "coupon_redemptions"("saleId");

-- CreateIndex
CREATE INDEX "coupon_redemptions_couponId_idx" ON "coupon_redemptions"("couponId");

-- CreateIndex
CREATE INDEX "coupon_redemptions_tenantId_createdAt_idx" ON "coupon_redemptions"("tenantId", "createdAt");

-- CreateIndex
CREATE INDEX "coupon_redemptions_tenantId_customerId_idx" ON "coupon_redemptions"("tenantId", "customerId");

-- CreateIndex
CREATE UNIQUE INDEX "promo_codes_code_key" ON "promo_codes"("code");

-- CreateIndex
CREATE INDEX "promo_redemptions_promoId_idx" ON "promo_redemptions"("promoId");

-- CreateIndex
CREATE UNIQUE INDEX "promo_redemptions_tenantId_key" ON "promo_redemptions"("tenantId");

-- CreateIndex
CREATE UNIQUE INDEX "referral_codes_code_key" ON "referral_codes"("code");

-- CreateIndex
CREATE UNIQUE INDEX "referrals_referredTenantId_key" ON "referrals"("referredTenantId");

-- CreateIndex
CREATE INDEX "referrals_referrerTenantId_status_idx" ON "referrals"("referrerTenantId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "statement_links_token_key" ON "statement_links"("token");

-- CreateIndex
CREATE INDEX "statement_links_tenantId_customerId_idx" ON "statement_links"("tenantId", "customerId");

-- CreateIndex
CREATE INDEX "statement_links_tenantId_debtorId_idx" ON "statement_links"("tenantId", "debtorId");

-- CreateIndex
CREATE INDEX "statement_claims_tenantId_status_createdAt_idx" ON "statement_claims"("tenantId", "status", "createdAt");

-- CreateIndex
CREATE INDEX "statement_claims_linkId_idx" ON "statement_claims"("linkId");

-- CreateIndex
CREATE INDEX "mpesa_entries_tenantId_status_createdAt_idx" ON "mpesa_entries"("tenantId", "status", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "mpesa_entries_tenantId_code_key" ON "mpesa_entries"("tenantId", "code");

-- AddForeignKey
ALTER TABLE "coupon_redemptions" ADD CONSTRAINT "coupon_redemptions_couponId_fkey" FOREIGN KEY ("couponId") REFERENCES "coupons"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "promo_redemptions" ADD CONSTRAINT "promo_redemptions_promoId_fkey" FOREIGN KEY ("promoId") REFERENCES "promo_codes"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "statement_claims" ADD CONSTRAINT "statement_claims_linkId_fkey" FOREIGN KEY ("linkId") REFERENCES "statement_links"("id") ON DELETE CASCADE ON UPDATE CASCADE;

