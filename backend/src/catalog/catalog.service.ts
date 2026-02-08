import {
  Injectable,
  NotFoundException,
  ConflictException,
} from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
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
  ) {}

  // ==================== CATEGORY OPERATIONS ====================

  async createCategory(tenantId: string, dto: CreateCategoryDto) {
    const existing = await this.prisma.category.findFirst({
      where: { tenantId, slug: dto.slug },
    });

    if (existing) {
      throw new ConflictException('Category with this slug already exists');
    }

    const category = await this.prisma.category.create({
      data: {
        tenantId,
        ...dto,
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
    const existing = await this.prisma.product.findFirst({
      where: { tenantId, sku: dto.sku },
    });

    if (existing) {
      throw new ConflictException('Product with this SKU already exists');
    }

    const { categoryIds, ...productData } = dto;

    const product = await this.prisma.product.create({
      data: {
        tenantId,
        ...productData,
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
      basePrice: Number(product.basePrice),
      costPrice: product.costPrice ? Number(product.costPrice) : undefined,
      taxRate: Number(product.taxRate),
      unit: product.unit,
      minStock: product.minStock,
      trackInventory: product.trackInventory,
      allowFractions: product.allowFractions,
      isActive: product.isActive,
      isFavorite: product.isFavorite,
      sortOrder: product.sortOrder,
      metadata: product.metadata,
      categories,
      currentPrice,
      currentStock,
    };
  }

  private async invalidateCategoryCache(tenantId: string) {
    await this.redisService.invalidatePattern(`categories:${tenantId}:*`);
  }

  private async invalidateProductCache(tenantId: string) {
    await this.redisService.invalidatePattern(`products:${tenantId}:*`);
  }
}
