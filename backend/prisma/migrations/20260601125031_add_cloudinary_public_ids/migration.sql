-- AlterTable
ALTER TABLE "categories" ADD COLUMN     "imagePublicId" TEXT;

-- AlterTable
ALTER TABLE "products" ADD COLUMN     "imagePublicId" TEXT;

-- AlterTable
ALTER TABLE "tenants" ADD COLUMN     "logoPublicId" TEXT;
