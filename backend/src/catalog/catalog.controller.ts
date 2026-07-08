import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  Query,
  UseGuards,
  Request,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiQuery,
} from '@nestjs/swagger';
import { CatalogService } from './catalog.service';
import {
  CreateCategoryDto,
  UpdateCategoryDto,
  CreateProductDto,
  UpdateProductDto,
  SetBranchPriceDto,
  ProductQueryDto,
  CategoryResponseDto,
  ProductResponseDto,
  PaginatedProductsDto,
} from './dto/catalog.dto';
import {
  BulkCreateProductsDto,
  BulkUpdateProductsDto,
  BulkDeleteProductsDto,
} from './dto/bulk-product.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { PermissionsGuard } from '../auth/guards/permissions.guard';
import { RequirePermissions } from '../auth/decorators/require-permissions.decorator';

@ApiTags('catalog')
@Controller({ path: 'catalog', version: '1' })
@UseGuards(JwtAuthGuard)
@ApiBearerAuth('JWT-auth')
export class CatalogController {
  constructor(private readonly catalogService: CatalogService) {}

  // ==================== CATEGORY ENDPOINTS ====================

  @Post('categories')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('categories.create')
  @ApiOperation({ summary: 'Create a new category' })
  @ApiResponse({ status: 201, description: 'Category created', type: CategoryResponseDto })
  async createCategory(@Request() req: any, @Body() dto: CreateCategoryDto) {
    return this.catalogService.createCategory(req.user.tenantId, dto);
  }

  @Get('categories')
  @ApiOperation({ summary: 'Get all categories (hierarchical)' })
  @ApiResponse({ status: 200, description: 'Category tree', type: [CategoryResponseDto] })
  @ApiQuery({ name: 'includeInactive', required: false, type: Boolean })
  async getCategories(
    @Request() req: any,
    @Query('includeInactive') includeInactive?: boolean,
  ) {
    return this.catalogService.getCategories(req.user.tenantId, includeInactive);
  }

  @Get('categories/:id')
  @ApiOperation({ summary: 'Get category by ID' })
  @ApiResponse({ status: 200, description: 'Category details', type: CategoryResponseDto })
  async getCategory(@Param('id') id: string, @Request() req: any) {
    return this.catalogService.getCategory(id, req.user.tenantId);
  }

  @Patch('categories/:id')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('categories.update')
  @ApiOperation({ summary: 'Update category' })
  @ApiResponse({ status: 200, description: 'Category updated', type: CategoryResponseDto })
  async updateCategory(
    @Param('id') id: string,
    @Request() req: any,
    @Body() dto: UpdateCategoryDto,
  ) {
    return this.catalogService.updateCategory(id, req.user.tenantId, dto);
  }

  @Delete('categories/:id')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('categories.delete')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Delete category (if empty)' })
  @ApiResponse({ status: 204, description: 'Category deleted' })
  async deleteCategory(@Param('id') id: string, @Request() req: any) {
    await this.catalogService.deleteCategory(id, req.user.tenantId);
  }

  // ==================== PRODUCT ENDPOINTS ====================

  @Post('products')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('products.create')
  @ApiOperation({ summary: 'Create a new product' })
  @ApiResponse({ status: 201, description: 'Product created', type: ProductResponseDto })
  async createProduct(@Request() req: any, @Body() dto: CreateProductDto) {
    return this.catalogService.createProduct(req.user.tenantId, dto);
  }

  @Get('products')
  @ApiOperation({ summary: 'Get products with filtering and pagination' })
  @ApiResponse({ status: 200, description: 'Paginated products', type: PaginatedProductsDto })
  @ApiQuery({ name: 'branchId', required: false, description: 'Get prices and stock for branch' })
  async getProducts(
    @Request() req: any,
    @Query() query: ProductQueryDto,
    @Query('branchId') branchId?: string,
  ) {
    return this.catalogService.getProducts(
      req.user.tenantId,
      query,
      branchId || req.user.branchId,
    );
  }

  @Get('products/favorites')
  @ApiOperation({ summary: 'Get favorite products' })
  @ApiResponse({ status: 200, description: 'Favorite products', type: [ProductResponseDto] })
  async getFavorites(
    @Request() req: any,
    @Query('branchId') branchId?: string,
  ) {
    return this.catalogService.getFavorites(
      req.user.tenantId,
      branchId || req.user.branchId,
    );
  }

  @Get('products/:id')
  @ApiOperation({ summary: 'Get product by ID' })
  @ApiResponse({ status: 200, description: 'Product details', type: ProductResponseDto })
  async getProduct(
    @Param('id') id: string,
    @Request() req: any,
    @Query('branchId') branchId?: string,
  ) {
    return this.catalogService.getProduct(
      id,
      req.user.tenantId,
      branchId || req.user.branchId,
    );
  }

  @Patch('products/:id')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('products.update')
  @ApiOperation({ summary: 'Update product' })
  @ApiResponse({ status: 200, description: 'Product updated', type: ProductResponseDto })
  async updateProduct(
    @Param('id') id: string,
    @Request() req: any,
    @Body() dto: UpdateProductDto,
  ) {
    return this.catalogService.updateProduct(id, req.user.tenantId, dto);
  }

  @Delete('products/:id')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('products.delete')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Delete product (if no sales)' })
  @ApiResponse({ status: 204, description: 'Product deleted' })
  async deleteProduct(@Param('id') id: string, @Request() req: any) {
    await this.catalogService.deleteProduct(id, req.user.tenantId);
  }

  @Post('products/:id/favorite')
  @ApiOperation({ summary: 'Toggle product favorite status' })
  @ApiResponse({ status: 200, description: 'Favorite toggled' })
  async toggleFavorite(@Param('id') id: string, @Request() req: any) {
    return this.catalogService.toggleFavorite(id, req.user.tenantId);
  }

  // ==================== BULK PRODUCT ENDPOINTS ====================

  @Post('products/bulk')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('products.bulk')
  @ApiOperation({ summary: 'Bulk create products' })
  @ApiResponse({ status: 201, description: 'Products created', type: [ProductResponseDto] })
  async bulkCreateProducts(@Request() req: any, @Body() dto: BulkCreateProductsDto) {
    return this.catalogService.bulkCreateProducts(req.user.tenantId, dto.products);
  }

  @Patch('products/bulk')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('products.bulk')
  @ApiOperation({ summary: 'Bulk update products' })
  @ApiResponse({ status: 200, description: 'Products updated', type: [ProductResponseDto] })
  async bulkUpdateProducts(@Request() req: any, @Body() dto: BulkUpdateProductsDto) {
    return this.catalogService.bulkUpdateProducts(req.user.tenantId, dto.products);
  }

  @Delete('products/bulk')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('products.bulk')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Bulk delete products (if no sales)' })
  @ApiResponse({ status: 204, description: 'Products deleted' })
  async bulkDeleteProducts(@Request() req: any, @Body() dto: BulkDeleteProductsDto) {
    await this.catalogService.bulkDeleteProducts(req.user.tenantId, dto.ids);
  }

  // ==================== PRICING ENDPOINTS ====================

  @Post('pricing')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('pricing.set')
  @ApiOperation({ summary: 'Set branch-specific price for a product' })
  @ApiResponse({ status: 201, description: 'Price override created' })
  async setBranchPrice(@Request() req: any, @Body() dto: SetBranchPriceDto) {
    return this.catalogService.setBranchPrice(req.user.tenantId, dto);
  }

  @Get('pricing/:branchId')
  @ApiOperation({ summary: 'Get all price overrides for a branch' })
  @ApiResponse({ status: 200, description: 'Branch price overrides' })
  async getBranchPrices(@Param('branchId') branchId: string, @Request() req: any) {
    return this.catalogService.getBranchPrices(branchId, req.user.tenantId);
  }

  @Delete('pricing/:productId/:branchId')
  @UseGuards(PermissionsGuard)
  @RequirePermissions('pricing.delete')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Remove branch-specific price' })
  @ApiResponse({ status: 204, description: 'Price override removed' })
  async removeBranchPrice(
    @Param('productId') productId: string,
    @Param('branchId') branchId: string,
    @Request() req: any,
  ) {
    await this.catalogService.removeBranchPrice(productId, branchId, req.user.tenantId);
  }
}
