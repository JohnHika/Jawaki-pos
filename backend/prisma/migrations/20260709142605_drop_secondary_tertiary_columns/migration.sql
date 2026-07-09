/*
  Warnings:

  - You are about to drop the column `secondaryUnit` on the `products` table. All the data in the column will be lost.
  - You are about to drop the column `secondaryUnitPrice` on the `products` table. All the data in the column will be lost.
  - You are about to drop the column `secondaryUnitQty` on the `products` table. All the data in the column will be lost.
  - You are about to drop the column `tertiaryUnit` on the `products` table. All the data in the column will be lost.
  - You are about to drop the column `tertiaryUnitPrice` on the `products` table. All the data in the column will be lost.
  - You are about to drop the column `tertiaryUnitQty` on the `products` table. All the data in the column will be lost.

*/
-- AlterTable
ALTER TABLE "products" DROP COLUMN "secondaryUnit",
DROP COLUMN "secondaryUnitPrice",
DROP COLUMN "secondaryUnitQty",
DROP COLUMN "tertiaryUnit",
DROP COLUMN "tertiaryUnitPrice",
DROP COLUMN "tertiaryUnitQty";
