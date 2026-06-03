import {
  Injectable,
  NotFoundException,
  ConflictException,
} from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { UploadsService } from '../uploads/uploads.service';
import {
  CreateCategoryDto,
  UpdateCategoryDto,
  CreateProductDto,
  UpdateProductDto,
  SetBranchPriceDto,
  ProductQueryDto,
} from './dto/catalog.dto';

@Injectable()
export class CatalogService {
  constructor(
    private prisma: PrismaService,
    private redisService: RedisService,
    private uploadsService: UploadsService,
  ) {}

  // ==================== CATEGORY OPERATIONS ====================

  async createCategory(tenantId: string, dto: CreateCategoryDto) {
    const slug = dto.slug || this.slugify(dto.name);
    const existing = await this.prisma.category.findFirst({
      where: { tenantId, slug },
    });

    if (existing) {
      throw new ConflictException('Category with this slug already exists');
    }

    const category = await this.prisma.category.create({
      data: {
        tenantId,
        ...dto,
        slug,
      },
    });

    await this.invalidateCategoryCache(tenantId);
    return category;
  }

  async getCategories(tenantId: string, includeInactive = false) {
    const cacheKey = `categories:${tenantId}:${includeInactive}`;
    const cached = await this.redisService.getJson<any[]>(cacheKey);
    if (cached) return cached;

    const categories = await this.prisma.category.findMany({
      where: {
        tenantId,
        ...(includeInactive ? {} : { isActive: true }),
      },
      include: {
        _count: {
          select: { products: true },
        },
      },
      orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
    });

    // Build hierarchical structure
    const result = this.buildCategoryTree(categories);
    await this.redisService.setJson(cacheKey, result, 300);
    return result;
  }

  async getCategory(categoryId: string, tenantId: string) {
    const category = await this.prisma.category.findFirst({
      where: { id: categoryId, tenantId },
      include: {
        parent: true,
        children: true,
        _count: {
          select: { products: true },
        },
      },
    });

    if (!category) {
      throw new NotFoundException('Category not found');
    }

    return {
      ...category,
      productCount: category._count.products,
      _count: undefined,
    };
  }

  async updateCategory(categoryId: string, tenantId: string, dto: UpdateCategoryDto) {
    const category = await this.prisma.category.findFirst({
      where: { id: categoryId, tenantId },
    });

    if (!category) {
      throw new NotFoundException('Category not found');
    }

    if (dto.slug && dto.slug !== category.slug) {
      const existing = await this.prisma.category.findFirst({
        where: {
          tenantId,
          slug: dto.slug,
          id: { not: categoryId },
        },
      });

      if (existing) {
        throw new ConflictException('Category with this slug already exists');
      }
    }

    const nextImage = (dto as any).image;
    // Clean up old Cloudinary image if image URL is being replaced or cleared.
    if (nextImage !== undefined && nextImage !== category.image && category.imagePublicId) {
      this.uploadsService.deleteImage(category.imagePublicId);
    }

    const updated = await this.prisma.category.update({
      where: { id: categoryId },
      data: dto,
    });

    await this.invalidateCategoryCache(tenantId);
    return updated;
  }

  async deleteCategory(categoryId: string, tenantId: string) {
    const category = await this.prisma.category.findFirst({
      where: { id: categoryId, tenantId },
      include: {
        _count: { select: { products: true, children: true } },
      },
    });

    if (!category) {
      throw new NotFoundException('Category not found');
    }

    if (category._count.products > 0 || category._count.children > 0) {
      throw new ConflictException(
        'Cannot delete category with products or subcategories',
      );
    }

    await this.prisma.category.delete({
      where: { id: categoryId },
    });

    await this.invalidateCategoryCache(tenantId);
  }

  // ==================== PRODUCT OPERATIONS ====================

  async createProduct(tenantId: string, dto: CreateProductDto) {
    const sku = dto.sku?.trim() || await this.generateUniqueSku(tenantId, dto.name);
    const existing = await this.prisma.product.findFirst({
      where: { tenantId, sku },
    });

    if (existing) {
      throw new ConflictException('Product with this SKU already exists');
    }

    const { categoryIds, ...productData } = dto;

    const product = await this.prisma.product.create({
      data: {
        tenantId,
        ...productData,
        sku,
        categories: categoryIds
          ? {
              create: categoryIds.map((categoryId) => ({ categoryId })),
            }
          : undefined,
      },
      include: {
        categories: {
          include: {
            category: {
              select: { id: true, name: true },
            },
          },
        },
      },
    });

    await this.invalidateProductCache(tenantId);
    return this.formatProduct(product);
  }

  async getProducts(tenantId: string, query: ProductQueryDto, branchId?: string) {
    const { search, categoryId, isActive, isFavorite, page = 1, limit = 50 } = query;
    const skip = (page - 1) * limit;

    const where: any = { tenantId };

    if (search) {
      where.OR = [
        { name: { contains: search, mode: 'insensitive' } },
        { sku: { contains: search, mode: 'insensitive' } },
        { description: { contains: search, mode: 'insensitive' } },
      ];
    }

    if (categoryId) {
      where.categories = {
        some: { categoryId },
      };
    }

    if (isActive !== undefined) {
      where.isActive = isActive;
    }

    if (isFavorite !== undefined) {
      where.isFavorite = isFavorite;
    }

    const [products, total] = await Promise.all([
      this.prisma.product.findMany({
        where,
        include: {
          categories: {
            include: {
              category: {
                select: { id: true, name: true },
              },
            },
          },
          priceOverrides: branchId
            ? { where: { branchId, isActive: true } }
            : false,
          stock: branchId ? { where: { branchId } } : false,
        },
        orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
        skip,
        take: limit,
      }),
      this.prisma.product.count({ where }),
    ]);

    const items = products.map((p) => this.formatProduct(p, branchId));

    return {
      items,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  async getProduct(productId: string, tenantId: string, branchId?: string) {
    const product = await this.prisma.product.findFirst({
      where: { id: productId, tenantId },
      include: {
        categories: {
          include: {
            category: {
              select: { id: true, name: true },
            },
          },
        },
        priceOverrides: branchId
          ? { where: { branchId, isActive: true } }
          : { where: { isActive: true } },
        stock: branchId ? { where: { branchId } } : true,
      },
    });

    if (!product) {
      throw new NotFoundException('Product not found');
    }

    return this.formatProduct(product, branchId);
  }

  async updateProduct(productId: string, tenantId: string, dto: UpdateProductDto) {
    const product = await this.prisma.product.findFirst({
      where: { id: productId, tenantId },
    });

    if (!product) {
      throw new NotFoundException('Product not found');
    }

    if (dto.sku && dto.sku !== product.sku) {
      const existing = await this.prisma.product.findFirst({
        where: {
          tenantId,
          sku: dto.sku,
          id: { not: productId },
        },
      });

      if (existing) {
        throw new ConflictException('Product with this SKU already exists');
      }
    }

    const nextImage = (dto as any).image;
    // Clean up old Cloudinary image if image URL is being replaced or cleared.
    if (nextImage !== undefined && nextImage !== product.image && product.imagePublicId) {
      this.uploadsService.deleteImage(product.imagePublicId);
    }

    const { categoryIds, ...updateData } = dto;

    // Update categories if provided
    if (categoryIds !== undefined) {
      await this.prisma.productCategory.deleteMany({
        where: { productId },
      });

      if (categoryIds.length > 0) {
        await this.prisma.productCategory.createMany({
          data: categoryIds.map((categoryId) => ({ productId, categoryId })),
        });
      }
    }

    const updated = await this.prisma.product.update({
      where: { id: productId },
      data: updateData,
      include: {
        categories: {
          include: {
            category: {
              select: { id: true, name: true },
            },
          },
        },
      },
    });

    await this.invalidateProductCache(tenantId);
    return this.formatProduct(updated);
  }

  async deleteProduct(productId: string, tenantId: string) {
    const product = await this.prisma.product.findFirst({
      where: { id: productId, tenantId },
      include: {
        _count: { select: { saleItems: true } },
      },
    });

    if (!product) {
      throw new NotFoundException('Product not found');
    }

    if (product._count.saleItems > 0) {
      throw new ConflictException(
        'Cannot delete product with sales history. Deactivate instead.',
      );
    }

    await this.prisma.product.delete({
      where: { id: productId },
    });

    await this.invalidateProductCache(tenantId);
  }

  // ==================== BULK PRODUCT OPERATIONS ====================

  async bulkCreateProducts(tenantId: string, products: any[]) {
    const results = await this.prisma.$transaction(
      products.map((dto) => {
        const { categoryIds, ...productData } = dto;
        return this.prisma.product.create({
          data: {
            tenantId,
            ...productData,
            categories: categoryIds
              ? { create: categoryIds.map((categoryId: string) => ({ categoryId })) }
              : undefined,
          },
          include: {
            categories: {
              include: {
                category: { select: { id: true, name: true } },
              },
            },
          },
        });
      }),
    );

    await this.invalidateProductCache(tenantId);
    return results.map((p) => this.formatProduct(p));
  }

  async bulkUpdateProducts(tenantId: string, products: { id: string; [key: string]: any }[]) {
    const results = await this.prisma.$transaction(async (tx) => {
      const updated: any[] = [];
      for (const item of products) {
        const { id, categoryIds, ...updateData } = item;

        const existing = await tx.product.findFirst({
          where: { id, tenantId },
        });
        if (!existing) {
          throw new NotFoundException(`Product ${id} not found`);
        }

        if (categoryIds !== undefined) {
          await tx.productCategory.deleteMany({ where: { productId: id } });
          if (categoryIds.length > 0) {
            await tx.productCategory.createMany({
              data: categoryIds.map((categoryId: string) => ({ productId: id, categoryId })),
            });
          }
        }

        const result = await tx.product.update({
          where: { id },
          data: updateData,
          include: {
            categories: {
              include: {
                category: { select: { id: true, name: true } },
              },
            },
          },
        });
        updated.push(result);
      }
      return updated;
    });

    await this.invalidateProductCache(tenantId);
    return results.map((p) => this.formatProduct(p));
  }

  async bulkDeleteProducts(tenantId: string, ids: string[]) {
    // Verify all products belong to tenant and have no sales
    const products = await this.prisma.product.findMany({
      where: { id: { in: ids }, tenantId },
      include: { _count: { select: { saleItems: true } } },
    });

    if (products.length !== ids.length) {
      const foundIds = products.map((p) => p.id);
      const missing = ids.filter((id) => !foundIds.includes(id));
      throw new NotFoundException(`Products not found: ${missing.join(', ')}`);
    }

    const withSales = products.filter((p) => p._count.saleItems > 0);
    if (withSales.length > 0) {
      throw new ConflictException(
        `Cannot delete products with sales history: ${withSales.map((p) => p.sku).join(', ')}. Deactivate instead.`,
      );
    }

    await this.prisma.$transaction([
      this.prisma.productCategory.deleteMany({ where: { productId: { in: ids } } }),
      this.prisma.branchPriceOverride.deleteMany({ where: { productId: { in: ids } } }),
      this.prisma.product.deleteMany({ where: { id: { in: ids } } }),
    ]);

    await this.invalidateProductCache(tenantId);
  }

  // ==================== PRICING OPERATIONS ====================

  async setBranchPrice(tenantId: string, dto: SetBranchPriceDto) {
    // Verify product and branch belong to tenant
    const [product, branch] = await Promise.all([
      this.prisma.product.findFirst({
        where: { id: dto.productId, tenantId },
      }),
      this.prisma.branch.findFirst({
        where: { id: dto.branchId, tenantId },
      }),
    ]);

    if (!product) {
      throw new NotFoundException('Product not found');
    }

    if (!branch) {
      throw new NotFoundException('Branch not found');
    }

    const override = await this.prisma.branchPriceOverride.upsert({
      where: {
        branchId_productId: {
          branchId: dto.branchId,
          productId: dto.productId,
        },
      },
      create: {
        branchId: dto.branchId,
        productId: dto.productId,
        price: dto.price,
        startDate: dto.startDate,
        endDate: dto.endDate,
      },
      update: {
        price: dto.price,
        startDate: dto.startDate,
        endDate: dto.endDate,
        isActive: true,
      },
    });

    await this.invalidateProductCache(tenantId);
    return override;
  }

  async removeBranchPrice(productId: string, branchId: string, tenantId: string) {
    const product = await this.prisma.product.findFirst({
      where: { id: productId, tenantId },
    });

    if (!product) {
      throw new NotFoundException('Product not found');
    }

    await this.prisma.branchPriceOverride.deleteMany({
      where: { productId, branchId },
    });

    await this.invalidateProductCache(tenantId);
  }

  async getBranchPrices(branchId: string, tenantId: string) {
    const branch = await this.prisma.branch.findFirst({
      where: { id: branchId, tenantId },
    });

    if (!branch) {
      throw new NotFoundException('Branch not found');
    }

    return this.prisma.branchPriceOverride.findMany({
      where: { branchId, isActive: true },
      include: {
        product: {
          select: {
            id: true,
            sku: true,
            name: true,
            basePrice: true,
          },
        },
      },
    });
  }

  // ==================== FAVORITES ====================

  async toggleFavorite(productId: string, tenantId: string) {
    const product = await this.prisma.product.findFirst({
      where: { id: productId, tenantId },
    });

    if (!product) {
      throw new NotFoundException('Product not found');
    }

    const updated = await this.prisma.product.update({
      where: { id: productId },
      data: { isFavorite: !product.isFavorite },
    });

    await this.invalidateProductCache(tenantId);
    return updated;
  }

  async getFavorites(tenantId: string, branchId?: string) {
    const products = await this.prisma.product.findMany({
      where: { tenantId, isFavorite: true, isActive: true },
      include: {
        categories: {
          include: {
            category: {
              select: { id: true, name: true },
            },
          },
        },
        priceOverrides: branchId
          ? { where: { branchId, isActive: true } }
          : false,
        stock: branchId ? { where: { branchId } } : false,
      },
      orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
    });

    return products.map((p) => this.formatProduct(p, branchId));
  }

  // ==================== HELPERS ====================

  private buildCategoryTree(categories: any[]) {
    const map = new Map();
    const roots: any[] = [];

    categories.forEach((cat) => {
      map.set(cat.id, {
        ...cat,
        imageUrl: cat.image,          // mobile catalog_provider expects 'imageUrl'
        productCount: cat._count.products,
        _count: undefined,
        children: [],
      });
    });

    categories.forEach((cat) => {
      const node = map.get(cat.id);
      if (cat.parentId && map.has(cat.parentId)) {
        map.get(cat.parentId).children.push(node);
      } else {
        roots.push(node);
      }
    });

    return roots;
  }

  private formatProduct(product: any, branchId?: string) {
    const categories = product.categories?.map((pc: any) => pc.category) || [];
    const categoryIds = categories.map((category: any) => category.id);
    
    // Determine current price
    let currentPrice = Number(product.basePrice);
    if (product.priceOverrides && product.priceOverrides.length > 0) {
      const override = product.priceOverrides[0];
      const now = new Date();
      const isValidPeriod =
        (!override.startDate || new Date(override.startDate) <= now) &&
        (!override.endDate || new Date(override.endDate) >= now);
      if (isValidPeriod) {
        currentPrice = Number(override.price);
      }
    }

    // Determine current stock
    let currentStock: number | undefined;
    if (product.stock && product.stock.length > 0) {
      currentStock = Number(product.stock[0].quantity);
    }

    return {
      id: product.id,
      sku: product.sku,
      name: product.name,
      description: product.description,
      image: product.image,
      imageUrl: product.image,
      imagePublicId: product.imagePublicId,
      categoryId: categoryIds[0],
      categoryIds,
      basePrice: Number(product.basePrice),
      price: currentPrice,
      costPrice: product.costPrice ? Number(product.costPrice) : undefined,
      taxRate: Number(product.taxRate),
      unit: product.unit,
      secondaryUnit: product.secondaryUnit ?? undefined,
      secondaryUnitQty: product.secondaryUnitQty ? Number(product.secondaryUnitQty) : undefined,
      tertiaryUnit: product.tertiaryUnit ?? undefined,
      tertiaryUnitQty: product.tertiaryUnitQty ? Number(product.tertiaryUnitQty) : undefined,
      minStock: product.minStock,
      trackInventory: product.trackInventory,
      allowFractions: product.allowFractions,
      isActive: product.isActive,
      isFavorite: product.isFavorite,
      sortOrder: product.sortOrder,
      metadata: product.metadata,
      createdAt: product.createdAt,
      updatedAt: product.updatedAt,
      categories,
      currentPrice,
      currentStock,
    };
  }

  private slugify(value: string): string {
    const slug = value
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 100)
      .replace(/-+$/g, '');

    return slug || 'category';
  }

  private async generateUniqueSku(tenantId: string, name: string): Promise<string> {
    const base = name
      .toUpperCase()
      .replace(/[^A-Z0-9]+/g, '')
      .slice(0, 8) || 'ITEM';

    for (let attempt = 0; attempt < 10; attempt += 1) {
      const suffix = `${Date.now()}`.slice(-4);
      const variant = attempt === 0 ? suffix : `${suffix}${attempt}`;
      const sku = `${base}-${variant}`;

      const existing = await this.prisma.product.findFirst({
        where: { tenantId, sku },
        select: { id: true },
      });

      if (!existing) {
        return sku;
      }
    }

    return `${base}-${Math.floor(1000 + Math.random() * 9000)}`;
  }

  private async invalidateCategoryCache(tenantId: string) {
    await this.redisService.invalidatePattern(`categories:${tenantId}:*`);
  }

  private async invalidateProductCache(tenantId: string) {
    await this.redisService.invalidatePattern(`products:${tenantId}:*`);
  }
}
