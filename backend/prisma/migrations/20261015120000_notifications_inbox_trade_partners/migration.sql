-- CreateTable
CREATE TABLE "app_notifications" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "tenantId" TEXT,
    "type" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "data" JSONB,
    "readAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "app_notifications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trade_partnerships" (
    "id" TEXT NOT NULL,
    "requesterTenantId" TEXT NOT NULL,
    "addresseeTenantId" TEXT NOT NULL,
    "requestedById" TEXT NOT NULL,
    "message" TEXT,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "respondedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "trade_partnerships_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "partner_messages" (
    "id" TEXT NOT NULL,
    "partnershipId" TEXT NOT NULL,
    "senderTenantId" TEXT NOT NULL,
    "senderUserId" TEXT NOT NULL,
    "senderName" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "readAt" TIMESTAMP(3),

    CONSTRAINT "partner_messages_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "app_notifications_userId_createdAt_idx" ON "app_notifications"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "app_notifications_userId_readAt_idx" ON "app_notifications"("userId", "readAt");

-- CreateIndex
CREATE INDEX "trade_partnerships_requesterTenantId_idx" ON "trade_partnerships"("requesterTenantId");

-- CreateIndex
CREATE INDEX "trade_partnerships_addresseeTenantId_idx" ON "trade_partnerships"("addresseeTenantId");

-- CreateIndex
CREATE UNIQUE INDEX "trade_partnerships_requesterTenantId_addresseeTenantId_key" ON "trade_partnerships"("requesterTenantId", "addresseeTenantId");

-- CreateIndex
CREATE INDEX "partner_messages_partnershipId_createdAt_idx" ON "partner_messages"("partnershipId", "createdAt");

-- AddForeignKey
ALTER TABLE "app_notifications" ADD CONSTRAINT "app_notifications_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trade_partnerships" ADD CONSTRAINT "trade_partnerships_requesterTenantId_fkey" FOREIGN KEY ("requesterTenantId") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trade_partnerships" ADD CONSTRAINT "trade_partnerships_addresseeTenantId_fkey" FOREIGN KEY ("addresseeTenantId") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "partner_messages" ADD CONSTRAINT "partner_messages_partnershipId_fkey" FOREIGN KEY ("partnershipId") REFERENCES "trade_partnerships"("id") ON DELETE CASCADE ON UPDATE CASCADE;

