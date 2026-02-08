// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _parentIdMeta =
      const VerificationMeta('parentId');
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
      'parent_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _imageUrlMeta =
      const VerificationMeta('imageUrl');
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
      'image_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        description,
        parentId,
        imageUrl,
        sortOrder,
        isActive,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(Insertable<Category> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('parent_id')) {
      context.handle(_parentIdMeta,
          parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta));
    }
    if (data.containsKey('image_url')) {
      context.handle(_imageUrlMeta,
          imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      parentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_id']),
      imageUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}image_url']),
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  final String id;
  final String name;
  final String? description;
  final String? parentId;
  final String? imageUrl;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Category(
      {required this.id,
      required this.name,
      this.description,
      this.parentId,
      this.imageUrl,
      required this.sortOrder,
      required this.isActive,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      sortOrder: Value(sortOrder),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Category.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'parentId': serializer.toJson<String?>(parentId),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Category copyWith(
          {String? id,
          String? name,
          Value<String?> description = const Value.absent(),
          Value<String?> parentId = const Value.absent(),
          Value<String?> imageUrl = const Value.absent(),
          int? sortOrder,
          bool? isActive,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Category(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description.present ? description.value : this.description,
        parentId: parentId.present ? parentId.value : this.parentId,
        imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
        sortOrder: sortOrder ?? this.sortOrder,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description:
          data.description.present ? data.description.value : this.description,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('parentId: $parentId, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, description, parentId, imageUrl,
      sortOrder, isActive, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.parentId == this.parentId &&
          other.imageUrl == this.imageUrl &&
          other.sortOrder == this.sortOrder &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<String?> parentId;
  final Value<String?> imageUrl;
  final Value<int> sortOrder;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.parentId = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String id,
    required String name,
    this.description = const Value.absent(),
    this.parentId = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isActive = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<Category> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? parentId,
    Expression<String>? imageUrl,
    Expression<int>? sortOrder,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (parentId != null) 'parent_id': parentId,
      if (imageUrl != null) 'image_url': imageUrl,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String?>? description,
      Value<String?>? parentId,
      Value<String?>? imageUrl,
      Value<int>? sortOrder,
      Value<bool>? isActive,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      parentId: parentId ?? this.parentId,
      imageUrl: imageUrl ?? this.imageUrl,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('parentId: $parentId, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductsTable extends Products with TableInfo<$ProductsTable, Product> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _skuMeta = const VerificationMeta('sku');
  @override
  late final GeneratedColumn<String> sku = GeneratedColumn<String>(
      'sku', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
      'category_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
      'price', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _costPriceMeta =
      const VerificationMeta('costPrice');
  @override
  late final GeneratedColumn<double> costPrice = GeneratedColumn<double>(
      'cost_price', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
      'unit', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('piece'));
  static const VerificationMeta _imageUrlMeta =
      const VerificationMeta('imageUrl');
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
      'image_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _trackInventoryMeta =
      const VerificationMeta('trackInventory');
  @override
  late final GeneratedColumn<bool> trackInventory = GeneratedColumn<bool>(
      'track_inventory', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("track_inventory" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        sku,
        name,
        description,
        categoryId,
        price,
        costPrice,
        unit,
        imageUrl,
        isActive,
        trackInventory,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'products';
  @override
  VerificationContext validateIntegrity(Insertable<Product> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('sku')) {
      context.handle(
          _skuMeta, sku.isAcceptableOrUnknown(data['sku']!, _skuMeta));
    } else if (isInserting) {
      context.missing(_skuMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
          _priceMeta, price.isAcceptableOrUnknown(data['price']!, _priceMeta));
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('cost_price')) {
      context.handle(_costPriceMeta,
          costPrice.isAcceptableOrUnknown(data['cost_price']!, _costPriceMeta));
    }
    if (data.containsKey('unit')) {
      context.handle(
          _unitMeta, unit.isAcceptableOrUnknown(data['unit']!, _unitMeta));
    }
    if (data.containsKey('image_url')) {
      context.handle(_imageUrlMeta,
          imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('track_inventory')) {
      context.handle(
          _trackInventoryMeta,
          trackInventory.isAcceptableOrUnknown(
              data['track_inventory']!, _trackInventoryMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Product map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Product(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      sku: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sku'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category_id'])!,
      price: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}price'])!,
      costPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}cost_price']),
      unit: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}unit'])!,
      imageUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}image_url']),
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      trackInventory: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}track_inventory'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ProductsTable createAlias(String alias) {
    return $ProductsTable(attachedDatabase, alias);
  }
}

class Product extends DataClass implements Insertable<Product> {
  final String id;
  final String sku;
  final String name;
  final String? description;
  final String categoryId;
  final double price;
  final double? costPrice;
  final String unit;
  final String? imageUrl;
  final bool isActive;
  final bool trackInventory;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Product(
      {required this.id,
      required this.sku,
      required this.name,
      this.description,
      required this.categoryId,
      required this.price,
      this.costPrice,
      required this.unit,
      this.imageUrl,
      required this.isActive,
      required this.trackInventory,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['sku'] = Variable<String>(sku);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['category_id'] = Variable<String>(categoryId);
    map['price'] = Variable<double>(price);
    if (!nullToAbsent || costPrice != null) {
      map['cost_price'] = Variable<double>(costPrice);
    }
    map['unit'] = Variable<String>(unit);
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['track_inventory'] = Variable<bool>(trackInventory);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProductsCompanion toCompanion(bool nullToAbsent) {
    return ProductsCompanion(
      id: Value(id),
      sku: Value(sku),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      categoryId: Value(categoryId),
      price: Value(price),
      costPrice: costPrice == null && nullToAbsent
          ? const Value.absent()
          : Value(costPrice),
      unit: Value(unit),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      isActive: Value(isActive),
      trackInventory: Value(trackInventory),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Product.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Product(
      id: serializer.fromJson<String>(json['id']),
      sku: serializer.fromJson<String>(json['sku']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      price: serializer.fromJson<double>(json['price']),
      costPrice: serializer.fromJson<double?>(json['costPrice']),
      unit: serializer.fromJson<String>(json['unit']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      trackInventory: serializer.fromJson<bool>(json['trackInventory']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sku': serializer.toJson<String>(sku),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'categoryId': serializer.toJson<String>(categoryId),
      'price': serializer.toJson<double>(price),
      'costPrice': serializer.toJson<double?>(costPrice),
      'unit': serializer.toJson<String>(unit),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'isActive': serializer.toJson<bool>(isActive),
      'trackInventory': serializer.toJson<bool>(trackInventory),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Product copyWith(
          {String? id,
          String? sku,
          String? name,
          Value<String?> description = const Value.absent(),
          String? categoryId,
          double? price,
          Value<double?> costPrice = const Value.absent(),
          String? unit,
          Value<String?> imageUrl = const Value.absent(),
          bool? isActive,
          bool? trackInventory,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Product(
        id: id ?? this.id,
        sku: sku ?? this.sku,
        name: name ?? this.name,
        description: description.present ? description.value : this.description,
        categoryId: categoryId ?? this.categoryId,
        price: price ?? this.price,
        costPrice: costPrice.present ? costPrice.value : this.costPrice,
        unit: unit ?? this.unit,
        imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
        isActive: isActive ?? this.isActive,
        trackInventory: trackInventory ?? this.trackInventory,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Product copyWithCompanion(ProductsCompanion data) {
    return Product(
      id: data.id.present ? data.id.value : this.id,
      sku: data.sku.present ? data.sku.value : this.sku,
      name: data.name.present ? data.name.value : this.name,
      description:
          data.description.present ? data.description.value : this.description,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      price: data.price.present ? data.price.value : this.price,
      costPrice: data.costPrice.present ? data.costPrice.value : this.costPrice,
      unit: data.unit.present ? data.unit.value : this.unit,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      trackInventory: data.trackInventory.present
          ? data.trackInventory.value
          : this.trackInventory,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Product(')
          ..write('id: $id, ')
          ..write('sku: $sku, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('categoryId: $categoryId, ')
          ..write('price: $price, ')
          ..write('costPrice: $costPrice, ')
          ..write('unit: $unit, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('isActive: $isActive, ')
          ..write('trackInventory: $trackInventory, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      sku,
      name,
      description,
      categoryId,
      price,
      costPrice,
      unit,
      imageUrl,
      isActive,
      trackInventory,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Product &&
          other.id == this.id &&
          other.sku == this.sku &&
          other.name == this.name &&
          other.description == this.description &&
          other.categoryId == this.categoryId &&
          other.price == this.price &&
          other.costPrice == this.costPrice &&
          other.unit == this.unit &&
          other.imageUrl == this.imageUrl &&
          other.isActive == this.isActive &&
          other.trackInventory == this.trackInventory &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProductsCompanion extends UpdateCompanion<Product> {
  final Value<String> id;
  final Value<String> sku;
  final Value<String> name;
  final Value<String?> description;
  final Value<String> categoryId;
  final Value<double> price;
  final Value<double?> costPrice;
  final Value<String> unit;
  final Value<String?> imageUrl;
  final Value<bool> isActive;
  final Value<bool> trackInventory;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ProductsCompanion({
    this.id = const Value.absent(),
    this.sku = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.price = const Value.absent(),
    this.costPrice = const Value.absent(),
    this.unit = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.isActive = const Value.absent(),
    this.trackInventory = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductsCompanion.insert({
    required String id,
    required String sku,
    required String name,
    this.description = const Value.absent(),
    required String categoryId,
    required double price,
    this.costPrice = const Value.absent(),
    this.unit = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.isActive = const Value.absent(),
    this.trackInventory = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        sku = Value(sku),
        name = Value(name),
        categoryId = Value(categoryId),
        price = Value(price),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<Product> custom({
    Expression<String>? id,
    Expression<String>? sku,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? categoryId,
    Expression<double>? price,
    Expression<double>? costPrice,
    Expression<String>? unit,
    Expression<String>? imageUrl,
    Expression<bool>? isActive,
    Expression<bool>? trackInventory,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sku != null) 'sku': sku,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (categoryId != null) 'category_id': categoryId,
      if (price != null) 'price': price,
      if (costPrice != null) 'cost_price': costPrice,
      if (unit != null) 'unit': unit,
      if (imageUrl != null) 'image_url': imageUrl,
      if (isActive != null) 'is_active': isActive,
      if (trackInventory != null) 'track_inventory': trackInventory,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductsCompanion copyWith(
      {Value<String>? id,
      Value<String>? sku,
      Value<String>? name,
      Value<String?>? description,
      Value<String>? categoryId,
      Value<double>? price,
      Value<double?>? costPrice,
      Value<String>? unit,
      Value<String?>? imageUrl,
      Value<bool>? isActive,
      Value<bool>? trackInventory,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return ProductsCompanion(
      id: id ?? this.id,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      price: price ?? this.price,
      costPrice: costPrice ?? this.costPrice,
      unit: unit ?? this.unit,
      imageUrl: imageUrl ?? this.imageUrl,
      isActive: isActive ?? this.isActive,
      trackInventory: trackInventory ?? this.trackInventory,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sku.present) {
      map['sku'] = Variable<String>(sku.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (costPrice.present) {
      map['cost_price'] = Variable<double>(costPrice.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (trackInventory.present) {
      map['track_inventory'] = Variable<bool>(trackInventory.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductsCompanion(')
          ..write('id: $id, ')
          ..write('sku: $sku, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('categoryId: $categoryId, ')
          ..write('price: $price, ')
          ..write('costPrice: $costPrice, ')
          ..write('unit: $unit, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('isActive: $isActive, ')
          ..write('trackInventory: $trackInventory, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BranchPricesTable extends BranchPrices
    with TableInfo<$BranchPricesTable, BranchPrice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BranchPricesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _branchIdMeta =
      const VerificationMeta('branchId');
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
      'branch_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
      'price', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _effectiveFromMeta =
      const VerificationMeta('effectiveFrom');
  @override
  late final GeneratedColumn<DateTime> effectiveFrom =
      GeneratedColumn<DateTime>('effective_from', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _effectiveToMeta =
      const VerificationMeta('effectiveTo');
  @override
  late final GeneratedColumn<DateTime> effectiveTo = GeneratedColumn<DateTime>(
      'effective_to', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, productId, branchId, price, effectiveFrom, effectiveTo];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'branch_prices';
  @override
  VerificationContext validateIntegrity(Insertable<BranchPrice> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(_branchIdMeta,
          branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta));
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
          _priceMeta, price.isAcceptableOrUnknown(data['price']!, _priceMeta));
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('effective_from')) {
      context.handle(
          _effectiveFromMeta,
          effectiveFrom.isAcceptableOrUnknown(
              data['effective_from']!, _effectiveFromMeta));
    }
    if (data.containsKey('effective_to')) {
      context.handle(
          _effectiveToMeta,
          effectiveTo.isAcceptableOrUnknown(
              data['effective_to']!, _effectiveToMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BranchPrice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BranchPrice(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      branchId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}branch_id'])!,
      price: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}price'])!,
      effectiveFrom: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}effective_from']),
      effectiveTo: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}effective_to']),
    );
  }

  @override
  $BranchPricesTable createAlias(String alias) {
    return $BranchPricesTable(attachedDatabase, alias);
  }
}

class BranchPrice extends DataClass implements Insertable<BranchPrice> {
  final String id;
  final String productId;
  final String branchId;
  final double price;
  final DateTime? effectiveFrom;
  final DateTime? effectiveTo;
  const BranchPrice(
      {required this.id,
      required this.productId,
      required this.branchId,
      required this.price,
      this.effectiveFrom,
      this.effectiveTo});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    map['branch_id'] = Variable<String>(branchId);
    map['price'] = Variable<double>(price);
    if (!nullToAbsent || effectiveFrom != null) {
      map['effective_from'] = Variable<DateTime>(effectiveFrom);
    }
    if (!nullToAbsent || effectiveTo != null) {
      map['effective_to'] = Variable<DateTime>(effectiveTo);
    }
    return map;
  }

  BranchPricesCompanion toCompanion(bool nullToAbsent) {
    return BranchPricesCompanion(
      id: Value(id),
      productId: Value(productId),
      branchId: Value(branchId),
      price: Value(price),
      effectiveFrom: effectiveFrom == null && nullToAbsent
          ? const Value.absent()
          : Value(effectiveFrom),
      effectiveTo: effectiveTo == null && nullToAbsent
          ? const Value.absent()
          : Value(effectiveTo),
    );
  }

  factory BranchPrice.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BranchPrice(
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      price: serializer.fromJson<double>(json['price']),
      effectiveFrom: serializer.fromJson<DateTime?>(json['effectiveFrom']),
      effectiveTo: serializer.fromJson<DateTime?>(json['effectiveTo']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'branchId': serializer.toJson<String>(branchId),
      'price': serializer.toJson<double>(price),
      'effectiveFrom': serializer.toJson<DateTime?>(effectiveFrom),
      'effectiveTo': serializer.toJson<DateTime?>(effectiveTo),
    };
  }

  BranchPrice copyWith(
          {String? id,
          String? productId,
          String? branchId,
          double? price,
          Value<DateTime?> effectiveFrom = const Value.absent(),
          Value<DateTime?> effectiveTo = const Value.absent()}) =>
      BranchPrice(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        branchId: branchId ?? this.branchId,
        price: price ?? this.price,
        effectiveFrom:
            effectiveFrom.present ? effectiveFrom.value : this.effectiveFrom,
        effectiveTo: effectiveTo.present ? effectiveTo.value : this.effectiveTo,
      );
  BranchPrice copyWithCompanion(BranchPricesCompanion data) {
    return BranchPrice(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      price: data.price.present ? data.price.value : this.price,
      effectiveFrom: data.effectiveFrom.present
          ? data.effectiveFrom.value
          : this.effectiveFrom,
      effectiveTo:
          data.effectiveTo.present ? data.effectiveTo.value : this.effectiveTo,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BranchPrice(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('branchId: $branchId, ')
          ..write('price: $price, ')
          ..write('effectiveFrom: $effectiveFrom, ')
          ..write('effectiveTo: $effectiveTo')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, productId, branchId, price, effectiveFrom, effectiveTo);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BranchPrice &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.branchId == this.branchId &&
          other.price == this.price &&
          other.effectiveFrom == this.effectiveFrom &&
          other.effectiveTo == this.effectiveTo);
}

class BranchPricesCompanion extends UpdateCompanion<BranchPrice> {
  final Value<String> id;
  final Value<String> productId;
  final Value<String> branchId;
  final Value<double> price;
  final Value<DateTime?> effectiveFrom;
  final Value<DateTime?> effectiveTo;
  final Value<int> rowid;
  const BranchPricesCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.price = const Value.absent(),
    this.effectiveFrom = const Value.absent(),
    this.effectiveTo = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BranchPricesCompanion.insert({
    required String id,
    required String productId,
    required String branchId,
    required double price,
    this.effectiveFrom = const Value.absent(),
    this.effectiveTo = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productId = Value(productId),
        branchId = Value(branchId),
        price = Value(price);
  static Insertable<BranchPrice> custom({
    Expression<String>? id,
    Expression<String>? productId,
    Expression<String>? branchId,
    Expression<double>? price,
    Expression<DateTime>? effectiveFrom,
    Expression<DateTime>? effectiveTo,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (branchId != null) 'branch_id': branchId,
      if (price != null) 'price': price,
      if (effectiveFrom != null) 'effective_from': effectiveFrom,
      if (effectiveTo != null) 'effective_to': effectiveTo,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BranchPricesCompanion copyWith(
      {Value<String>? id,
      Value<String>? productId,
      Value<String>? branchId,
      Value<double>? price,
      Value<DateTime?>? effectiveFrom,
      Value<DateTime?>? effectiveTo,
      Value<int>? rowid}) {
    return BranchPricesCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      branchId: branchId ?? this.branchId,
      price: price ?? this.price,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      effectiveTo: effectiveTo ?? this.effectiveTo,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (effectiveFrom.present) {
      map['effective_from'] = Variable<DateTime>(effectiveFrom.value);
    }
    if (effectiveTo.present) {
      map['effective_to'] = Variable<DateTime>(effectiveTo.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BranchPricesCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('branchId: $branchId, ')
          ..write('price: $price, ')
          ..write('effectiveFrom: $effectiveFrom, ')
          ..write('effectiveTo: $effectiveTo, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalStockTable extends LocalStock
    with TableInfo<$LocalStockTable, LocalStockData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalStockTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _branchIdMeta =
      const VerificationMeta('branchId');
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
      'branch_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _quantityMeta =
      const VerificationMeta('quantity');
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
      'quantity', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _minQuantityMeta =
      const VerificationMeta('minQuantity');
  @override
  late final GeneratedColumn<int> minQuantity = GeneratedColumn<int>(
      'min_quantity', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _maxQuantityMeta =
      const VerificationMeta('maxQuantity');
  @override
  late final GeneratedColumn<int> maxQuantity = GeneratedColumn<int>(
      'max_quantity', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, productId, branchId, quantity, minQuantity, maxQuantity, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_stock';
  @override
  VerificationContext validateIntegrity(Insertable<LocalStockData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(_branchIdMeta,
          branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta));
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(_quantityMeta,
          quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta));
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('min_quantity')) {
      context.handle(
          _minQuantityMeta,
          minQuantity.isAcceptableOrUnknown(
              data['min_quantity']!, _minQuantityMeta));
    }
    if (data.containsKey('max_quantity')) {
      context.handle(
          _maxQuantityMeta,
          maxQuantity.isAcceptableOrUnknown(
              data['max_quantity']!, _maxQuantityMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalStockData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalStockData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      branchId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}branch_id'])!,
      quantity: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}quantity'])!,
      minQuantity: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}min_quantity'])!,
      maxQuantity: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}max_quantity']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $LocalStockTable createAlias(String alias) {
    return $LocalStockTable(attachedDatabase, alias);
  }
}

class LocalStockData extends DataClass implements Insertable<LocalStockData> {
  final String id;
  final String productId;
  final String branchId;
  final int quantity;
  final int minQuantity;
  final int? maxQuantity;
  final DateTime updatedAt;
  const LocalStockData(
      {required this.id,
      required this.productId,
      required this.branchId,
      required this.quantity,
      required this.minQuantity,
      this.maxQuantity,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    map['branch_id'] = Variable<String>(branchId);
    map['quantity'] = Variable<int>(quantity);
    map['min_quantity'] = Variable<int>(minQuantity);
    if (!nullToAbsent || maxQuantity != null) {
      map['max_quantity'] = Variable<int>(maxQuantity);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalStockCompanion toCompanion(bool nullToAbsent) {
    return LocalStockCompanion(
      id: Value(id),
      productId: Value(productId),
      branchId: Value(branchId),
      quantity: Value(quantity),
      minQuantity: Value(minQuantity),
      maxQuantity: maxQuantity == null && nullToAbsent
          ? const Value.absent()
          : Value(maxQuantity),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalStockData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalStockData(
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      quantity: serializer.fromJson<int>(json['quantity']),
      minQuantity: serializer.fromJson<int>(json['minQuantity']),
      maxQuantity: serializer.fromJson<int?>(json['maxQuantity']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'branchId': serializer.toJson<String>(branchId),
      'quantity': serializer.toJson<int>(quantity),
      'minQuantity': serializer.toJson<int>(minQuantity),
      'maxQuantity': serializer.toJson<int?>(maxQuantity),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalStockData copyWith(
          {String? id,
          String? productId,
          String? branchId,
          int? quantity,
          int? minQuantity,
          Value<int?> maxQuantity = const Value.absent(),
          DateTime? updatedAt}) =>
      LocalStockData(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        branchId: branchId ?? this.branchId,
        quantity: quantity ?? this.quantity,
        minQuantity: minQuantity ?? this.minQuantity,
        maxQuantity: maxQuantity.present ? maxQuantity.value : this.maxQuantity,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  LocalStockData copyWithCompanion(LocalStockCompanion data) {
    return LocalStockData(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      minQuantity:
          data.minQuantity.present ? data.minQuantity.value : this.minQuantity,
      maxQuantity:
          data.maxQuantity.present ? data.maxQuantity.value : this.maxQuantity,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalStockData(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('branchId: $branchId, ')
          ..write('quantity: $quantity, ')
          ..write('minQuantity: $minQuantity, ')
          ..write('maxQuantity: $maxQuantity, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, productId, branchId, quantity, minQuantity, maxQuantity, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalStockData &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.branchId == this.branchId &&
          other.quantity == this.quantity &&
          other.minQuantity == this.minQuantity &&
          other.maxQuantity == this.maxQuantity &&
          other.updatedAt == this.updatedAt);
}

class LocalStockCompanion extends UpdateCompanion<LocalStockData> {
  final Value<String> id;
  final Value<String> productId;
  final Value<String> branchId;
  final Value<int> quantity;
  final Value<int> minQuantity;
  final Value<int?> maxQuantity;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalStockCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.quantity = const Value.absent(),
    this.minQuantity = const Value.absent(),
    this.maxQuantity = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalStockCompanion.insert({
    required String id,
    required String productId,
    required String branchId,
    required int quantity,
    this.minQuantity = const Value.absent(),
    this.maxQuantity = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productId = Value(productId),
        branchId = Value(branchId),
        quantity = Value(quantity),
        updatedAt = Value(updatedAt);
  static Insertable<LocalStockData> custom({
    Expression<String>? id,
    Expression<String>? productId,
    Expression<String>? branchId,
    Expression<int>? quantity,
    Expression<int>? minQuantity,
    Expression<int>? maxQuantity,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (branchId != null) 'branch_id': branchId,
      if (quantity != null) 'quantity': quantity,
      if (minQuantity != null) 'min_quantity': minQuantity,
      if (maxQuantity != null) 'max_quantity': maxQuantity,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalStockCompanion copyWith(
      {Value<String>? id,
      Value<String>? productId,
      Value<String>? branchId,
      Value<int>? quantity,
      Value<int>? minQuantity,
      Value<int?>? maxQuantity,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return LocalStockCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      branchId: branchId ?? this.branchId,
      quantity: quantity ?? this.quantity,
      minQuantity: minQuantity ?? this.minQuantity,
      maxQuantity: maxQuantity ?? this.maxQuantity,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (minQuantity.present) {
      map['min_quantity'] = Variable<int>(minQuantity.value);
    }
    if (maxQuantity.present) {
      map['max_quantity'] = Variable<int>(maxQuantity.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalStockCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('branchId: $branchId, ')
          ..write('quantity: $quantity, ')
          ..write('minQuantity: $minQuantity, ')
          ..write('maxQuantity: $maxQuantity, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CartItemsTable extends CartItems
    with TableInfo<$CartItemsTable, CartItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CartItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productNameMeta =
      const VerificationMeta('productName');
  @override
  late final GeneratedColumn<String> productName = GeneratedColumn<String>(
      'product_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _skuMeta = const VerificationMeta('sku');
  @override
  late final GeneratedColumn<String> sku = GeneratedColumn<String>(
      'sku', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _quantityMeta =
      const VerificationMeta('quantity');
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
      'quantity', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _unitPriceMeta =
      const VerificationMeta('unitPrice');
  @override
  late final GeneratedColumn<double> unitPrice = GeneratedColumn<double>(
      'unit_price', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _discountMeta =
      const VerificationMeta('discount');
  @override
  late final GeneratedColumn<double> discount = GeneratedColumn<double>(
      'discount', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _totalMeta = const VerificationMeta('total');
  @override
  late final GeneratedColumn<double> total = GeneratedColumn<double>(
      'total', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _addedAtMeta =
      const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
      'added_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        productId,
        productName,
        sku,
        quantity,
        unitPrice,
        discount,
        total,
        notes,
        addedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cart_items';
  @override
  VerificationContext validateIntegrity(Insertable<CartItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('product_name')) {
      context.handle(
          _productNameMeta,
          productName.isAcceptableOrUnknown(
              data['product_name']!, _productNameMeta));
    } else if (isInserting) {
      context.missing(_productNameMeta);
    }
    if (data.containsKey('sku')) {
      context.handle(
          _skuMeta, sku.isAcceptableOrUnknown(data['sku']!, _skuMeta));
    } else if (isInserting) {
      context.missing(_skuMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(_quantityMeta,
          quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta));
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('unit_price')) {
      context.handle(_unitPriceMeta,
          unitPrice.isAcceptableOrUnknown(data['unit_price']!, _unitPriceMeta));
    } else if (isInserting) {
      context.missing(_unitPriceMeta);
    }
    if (data.containsKey('discount')) {
      context.handle(_discountMeta,
          discount.isAcceptableOrUnknown(data['discount']!, _discountMeta));
    }
    if (data.containsKey('total')) {
      context.handle(
          _totalMeta, total.isAcceptableOrUnknown(data['total']!, _totalMeta));
    } else if (isInserting) {
      context.missing(_totalMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta,
          addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CartItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CartItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      productName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_name'])!,
      sku: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sku'])!,
      quantity: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}quantity'])!,
      unitPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}unit_price'])!,
      discount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}discount'])!,
      total: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}total'])!,
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes']),
      addedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}added_at'])!,
    );
  }

  @override
  $CartItemsTable createAlias(String alias) {
    return $CartItemsTable(attachedDatabase, alias);
  }
}

class CartItem extends DataClass implements Insertable<CartItem> {
  final int id;
  final String productId;
  final String productName;
  final String sku;
  final int quantity;
  final double unitPrice;
  final double discount;
  final double total;
  final String? notes;
  final DateTime addedAt;
  const CartItem(
      {required this.id,
      required this.productId,
      required this.productName,
      required this.sku,
      required this.quantity,
      required this.unitPrice,
      required this.discount,
      required this.total,
      this.notes,
      required this.addedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['product_id'] = Variable<String>(productId);
    map['product_name'] = Variable<String>(productName);
    map['sku'] = Variable<String>(sku);
    map['quantity'] = Variable<int>(quantity);
    map['unit_price'] = Variable<double>(unitPrice);
    map['discount'] = Variable<double>(discount);
    map['total'] = Variable<double>(total);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  CartItemsCompanion toCompanion(bool nullToAbsent) {
    return CartItemsCompanion(
      id: Value(id),
      productId: Value(productId),
      productName: Value(productName),
      sku: Value(sku),
      quantity: Value(quantity),
      unitPrice: Value(unitPrice),
      discount: Value(discount),
      total: Value(total),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
      addedAt: Value(addedAt),
    );
  }

  factory CartItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CartItem(
      id: serializer.fromJson<int>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      productName: serializer.fromJson<String>(json['productName']),
      sku: serializer.fromJson<String>(json['sku']),
      quantity: serializer.fromJson<int>(json['quantity']),
      unitPrice: serializer.fromJson<double>(json['unitPrice']),
      discount: serializer.fromJson<double>(json['discount']),
      total: serializer.fromJson<double>(json['total']),
      notes: serializer.fromJson<String?>(json['notes']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'productId': serializer.toJson<String>(productId),
      'productName': serializer.toJson<String>(productName),
      'sku': serializer.toJson<String>(sku),
      'quantity': serializer.toJson<int>(quantity),
      'unitPrice': serializer.toJson<double>(unitPrice),
      'discount': serializer.toJson<double>(discount),
      'total': serializer.toJson<double>(total),
      'notes': serializer.toJson<String?>(notes),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  CartItem copyWith(
          {int? id,
          String? productId,
          String? productName,
          String? sku,
          int? quantity,
          double? unitPrice,
          double? discount,
          double? total,
          Value<String?> notes = const Value.absent(),
          DateTime? addedAt}) =>
      CartItem(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        productName: productName ?? this.productName,
        sku: sku ?? this.sku,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        discount: discount ?? this.discount,
        total: total ?? this.total,
        notes: notes.present ? notes.value : this.notes,
        addedAt: addedAt ?? this.addedAt,
      );
  CartItem copyWithCompanion(CartItemsCompanion data) {
    return CartItem(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      productName:
          data.productName.present ? data.productName.value : this.productName,
      sku: data.sku.present ? data.sku.value : this.sku,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      unitPrice: data.unitPrice.present ? data.unitPrice.value : this.unitPrice,
      discount: data.discount.present ? data.discount.value : this.discount,
      total: data.total.present ? data.total.value : this.total,
      notes: data.notes.present ? data.notes.value : this.notes,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CartItem(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('productName: $productName, ')
          ..write('sku: $sku, ')
          ..write('quantity: $quantity, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('discount: $discount, ')
          ..write('total: $total, ')
          ..write('notes: $notes, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, productId, productName, sku, quantity,
      unitPrice, discount, total, notes, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CartItem &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.productName == this.productName &&
          other.sku == this.sku &&
          other.quantity == this.quantity &&
          other.unitPrice == this.unitPrice &&
          other.discount == this.discount &&
          other.total == this.total &&
          other.notes == this.notes &&
          other.addedAt == this.addedAt);
}

class CartItemsCompanion extends UpdateCompanion<CartItem> {
  final Value<int> id;
  final Value<String> productId;
  final Value<String> productName;
  final Value<String> sku;
  final Value<int> quantity;
  final Value<double> unitPrice;
  final Value<double> discount;
  final Value<double> total;
  final Value<String?> notes;
  final Value<DateTime> addedAt;
  const CartItemsCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.productName = const Value.absent(),
    this.sku = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unitPrice = const Value.absent(),
    this.discount = const Value.absent(),
    this.total = const Value.absent(),
    this.notes = const Value.absent(),
    this.addedAt = const Value.absent(),
  });
  CartItemsCompanion.insert({
    this.id = const Value.absent(),
    required String productId,
    required String productName,
    required String sku,
    required int quantity,
    required double unitPrice,
    this.discount = const Value.absent(),
    required double total,
    this.notes = const Value.absent(),
    required DateTime addedAt,
  })  : productId = Value(productId),
        productName = Value(productName),
        sku = Value(sku),
        quantity = Value(quantity),
        unitPrice = Value(unitPrice),
        total = Value(total),
        addedAt = Value(addedAt);
  static Insertable<CartItem> custom({
    Expression<int>? id,
    Expression<String>? productId,
    Expression<String>? productName,
    Expression<String>? sku,
    Expression<int>? quantity,
    Expression<double>? unitPrice,
    Expression<double>? discount,
    Expression<double>? total,
    Expression<String>? notes,
    Expression<DateTime>? addedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (productName != null) 'product_name': productName,
      if (sku != null) 'sku': sku,
      if (quantity != null) 'quantity': quantity,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (discount != null) 'discount': discount,
      if (total != null) 'total': total,
      if (notes != null) 'notes': notes,
      if (addedAt != null) 'added_at': addedAt,
    });
  }

  CartItemsCompanion copyWith(
      {Value<int>? id,
      Value<String>? productId,
      Value<String>? productName,
      Value<String>? sku,
      Value<int>? quantity,
      Value<double>? unitPrice,
      Value<double>? discount,
      Value<double>? total,
      Value<String?>? notes,
      Value<DateTime>? addedAt}) {
    return CartItemsCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      sku: sku ?? this.sku,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discount: discount ?? this.discount,
      total: total ?? this.total,
      notes: notes ?? this.notes,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (productName.present) {
      map['product_name'] = Variable<String>(productName.value);
    }
    if (sku.present) {
      map['sku'] = Variable<String>(sku.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (unitPrice.present) {
      map['unit_price'] = Variable<double>(unitPrice.value);
    }
    if (discount.present) {
      map['discount'] = Variable<double>(discount.value);
    }
    if (total.present) {
      map['total'] = Variable<double>(total.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CartItemsCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('productName: $productName, ')
          ..write('sku: $sku, ')
          ..write('quantity: $quantity, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('discount: $discount, ')
          ..write('total: $total, ')
          ..write('notes: $notes, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }
}

class $PendingSalesTable extends PendingSales
    with TableInfo<$PendingSalesTable, PendingSale> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingSalesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _receiptNumberMeta =
      const VerificationMeta('receiptNumber');
  @override
  late final GeneratedColumn<String> receiptNumber = GeneratedColumn<String>(
      'receipt_number', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _subtotalMeta =
      const VerificationMeta('subtotal');
  @override
  late final GeneratedColumn<double> subtotal = GeneratedColumn<double>(
      'subtotal', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _discountMeta =
      const VerificationMeta('discount');
  @override
  late final GeneratedColumn<double> discount = GeneratedColumn<double>(
      'discount', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _taxMeta = const VerificationMeta('tax');
  @override
  late final GeneratedColumn<double> tax = GeneratedColumn<double>(
      'tax', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _totalMeta = const VerificationMeta('total');
  @override
  late final GeneratedColumn<double> total = GeneratedColumn<double>(
      'total', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _paymentMethodMeta =
      const VerificationMeta('paymentMethod');
  @override
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
      'payment_method', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _paymentReferenceMeta =
      const VerificationMeta('paymentReference');
  @override
  late final GeneratedColumn<String> paymentReference = GeneratedColumn<String>(
      'payment_reference', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _customerIdMeta =
      const VerificationMeta('customerId');
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
      'customer_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _cashierIdMeta =
      const VerificationMeta('cashierId');
  @override
  late final GeneratedColumn<String> cashierId = GeneratedColumn<String>(
      'cashier_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _branchIdMeta =
      const VerificationMeta('branchId');
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
      'branch_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('PENDING'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _isSyncedMeta =
      const VerificationMeta('isSynced');
  @override
  late final GeneratedColumn<bool> isSynced = GeneratedColumn<bool>(
      'is_synced', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_synced" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _syncedAtMeta =
      const VerificationMeta('syncedAt');
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
      'synced_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        receiptNumber,
        subtotal,
        discount,
        tax,
        total,
        paymentMethod,
        paymentReference,
        customerId,
        cashierId,
        branchId,
        notes,
        status,
        createdAt,
        isSynced,
        syncedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_sales';
  @override
  VerificationContext validateIntegrity(Insertable<PendingSale> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('receipt_number')) {
      context.handle(
          _receiptNumberMeta,
          receiptNumber.isAcceptableOrUnknown(
              data['receipt_number']!, _receiptNumberMeta));
    } else if (isInserting) {
      context.missing(_receiptNumberMeta);
    }
    if (data.containsKey('subtotal')) {
      context.handle(_subtotalMeta,
          subtotal.isAcceptableOrUnknown(data['subtotal']!, _subtotalMeta));
    } else if (isInserting) {
      context.missing(_subtotalMeta);
    }
    if (data.containsKey('discount')) {
      context.handle(_discountMeta,
          discount.isAcceptableOrUnknown(data['discount']!, _discountMeta));
    }
    if (data.containsKey('tax')) {
      context.handle(
          _taxMeta, tax.isAcceptableOrUnknown(data['tax']!, _taxMeta));
    }
    if (data.containsKey('total')) {
      context.handle(
          _totalMeta, total.isAcceptableOrUnknown(data['total']!, _totalMeta));
    } else if (isInserting) {
      context.missing(_totalMeta);
    }
    if (data.containsKey('payment_method')) {
      context.handle(
          _paymentMethodMeta,
          paymentMethod.isAcceptableOrUnknown(
              data['payment_method']!, _paymentMethodMeta));
    } else if (isInserting) {
      context.missing(_paymentMethodMeta);
    }
    if (data.containsKey('payment_reference')) {
      context.handle(
          _paymentReferenceMeta,
          paymentReference.isAcceptableOrUnknown(
              data['payment_reference']!, _paymentReferenceMeta));
    }
    if (data.containsKey('customer_id')) {
      context.handle(
          _customerIdMeta,
          customerId.isAcceptableOrUnknown(
              data['customer_id']!, _customerIdMeta));
    }
    if (data.containsKey('cashier_id')) {
      context.handle(_cashierIdMeta,
          cashierId.isAcceptableOrUnknown(data['cashier_id']!, _cashierIdMeta));
    } else if (isInserting) {
      context.missing(_cashierIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(_branchIdMeta,
          branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta));
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('is_synced')) {
      context.handle(_isSyncedMeta,
          isSynced.isAcceptableOrUnknown(data['is_synced']!, _isSyncedMeta));
    }
    if (data.containsKey('synced_at')) {
      context.handle(_syncedAtMeta,
          syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingSale map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingSale(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      receiptNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}receipt_number'])!,
      subtotal: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}subtotal'])!,
      discount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}discount'])!,
      tax: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}tax'])!,
      total: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}total'])!,
      paymentMethod: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payment_method'])!,
      paymentReference: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}payment_reference']),
      customerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}customer_id']),
      cashierId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cashier_id'])!,
      branchId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}branch_id'])!,
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      isSynced: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_synced'])!,
      syncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}synced_at']),
    );
  }

  @override
  $PendingSalesTable createAlias(String alias) {
    return $PendingSalesTable(attachedDatabase, alias);
  }
}

class PendingSale extends DataClass implements Insertable<PendingSale> {
  final String id;
  final String receiptNumber;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final String paymentMethod;
  final String? paymentReference;
  final String? customerId;
  final String cashierId;
  final String branchId;
  final String? notes;
  final String status;
  final DateTime createdAt;
  final bool isSynced;
  final DateTime? syncedAt;
  const PendingSale(
      {required this.id,
      required this.receiptNumber,
      required this.subtotal,
      required this.discount,
      required this.tax,
      required this.total,
      required this.paymentMethod,
      this.paymentReference,
      this.customerId,
      required this.cashierId,
      required this.branchId,
      this.notes,
      required this.status,
      required this.createdAt,
      required this.isSynced,
      this.syncedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['receipt_number'] = Variable<String>(receiptNumber);
    map['subtotal'] = Variable<double>(subtotal);
    map['discount'] = Variable<double>(discount);
    map['tax'] = Variable<double>(tax);
    map['total'] = Variable<double>(total);
    map['payment_method'] = Variable<String>(paymentMethod);
    if (!nullToAbsent || paymentReference != null) {
      map['payment_reference'] = Variable<String>(paymentReference);
    }
    if (!nullToAbsent || customerId != null) {
      map['customer_id'] = Variable<String>(customerId);
    }
    map['cashier_id'] = Variable<String>(cashierId);
    map['branch_id'] = Variable<String>(branchId);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['is_synced'] = Variable<bool>(isSynced);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    return map;
  }

  PendingSalesCompanion toCompanion(bool nullToAbsent) {
    return PendingSalesCompanion(
      id: Value(id),
      receiptNumber: Value(receiptNumber),
      subtotal: Value(subtotal),
      discount: Value(discount),
      tax: Value(tax),
      total: Value(total),
      paymentMethod: Value(paymentMethod),
      paymentReference: paymentReference == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentReference),
      customerId: customerId == null && nullToAbsent
          ? const Value.absent()
          : Value(customerId),
      cashierId: Value(cashierId),
      branchId: Value(branchId),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
      status: Value(status),
      createdAt: Value(createdAt),
      isSynced: Value(isSynced),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
    );
  }

  factory PendingSale.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingSale(
      id: serializer.fromJson<String>(json['id']),
      receiptNumber: serializer.fromJson<String>(json['receiptNumber']),
      subtotal: serializer.fromJson<double>(json['subtotal']),
      discount: serializer.fromJson<double>(json['discount']),
      tax: serializer.fromJson<double>(json['tax']),
      total: serializer.fromJson<double>(json['total']),
      paymentMethod: serializer.fromJson<String>(json['paymentMethod']),
      paymentReference: serializer.fromJson<String?>(json['paymentReference']),
      customerId: serializer.fromJson<String?>(json['customerId']),
      cashierId: serializer.fromJson<String>(json['cashierId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      notes: serializer.fromJson<String?>(json['notes']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      isSynced: serializer.fromJson<bool>(json['isSynced']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'receiptNumber': serializer.toJson<String>(receiptNumber),
      'subtotal': serializer.toJson<double>(subtotal),
      'discount': serializer.toJson<double>(discount),
      'tax': serializer.toJson<double>(tax),
      'total': serializer.toJson<double>(total),
      'paymentMethod': serializer.toJson<String>(paymentMethod),
      'paymentReference': serializer.toJson<String?>(paymentReference),
      'customerId': serializer.toJson<String?>(customerId),
      'cashierId': serializer.toJson<String>(cashierId),
      'branchId': serializer.toJson<String>(branchId),
      'notes': serializer.toJson<String?>(notes),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'isSynced': serializer.toJson<bool>(isSynced),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
    };
  }

  PendingSale copyWith(
          {String? id,
          String? receiptNumber,
          double? subtotal,
          double? discount,
          double? tax,
          double? total,
          String? paymentMethod,
          Value<String?> paymentReference = const Value.absent(),
          Value<String?> customerId = const Value.absent(),
          String? cashierId,
          String? branchId,
          Value<String?> notes = const Value.absent(),
          String? status,
          DateTime? createdAt,
          bool? isSynced,
          Value<DateTime?> syncedAt = const Value.absent()}) =>
      PendingSale(
        id: id ?? this.id,
        receiptNumber: receiptNumber ?? this.receiptNumber,
        subtotal: subtotal ?? this.subtotal,
        discount: discount ?? this.discount,
        tax: tax ?? this.tax,
        total: total ?? this.total,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        paymentReference: paymentReference.present
            ? paymentReference.value
            : this.paymentReference,
        customerId: customerId.present ? customerId.value : this.customerId,
        cashierId: cashierId ?? this.cashierId,
        branchId: branchId ?? this.branchId,
        notes: notes.present ? notes.value : this.notes,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        isSynced: isSynced ?? this.isSynced,
        syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
      );
  PendingSale copyWithCompanion(PendingSalesCompanion data) {
    return PendingSale(
      id: data.id.present ? data.id.value : this.id,
      receiptNumber: data.receiptNumber.present
          ? data.receiptNumber.value
          : this.receiptNumber,
      subtotal: data.subtotal.present ? data.subtotal.value : this.subtotal,
      discount: data.discount.present ? data.discount.value : this.discount,
      tax: data.tax.present ? data.tax.value : this.tax,
      total: data.total.present ? data.total.value : this.total,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      paymentReference: data.paymentReference.present
          ? data.paymentReference.value
          : this.paymentReference,
      customerId:
          data.customerId.present ? data.customerId.value : this.customerId,
      cashierId: data.cashierId.present ? data.cashierId.value : this.cashierId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      notes: data.notes.present ? data.notes.value : this.notes,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      isSynced: data.isSynced.present ? data.isSynced.value : this.isSynced,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingSale(')
          ..write('id: $id, ')
          ..write('receiptNumber: $receiptNumber, ')
          ..write('subtotal: $subtotal, ')
          ..write('discount: $discount, ')
          ..write('tax: $tax, ')
          ..write('total: $total, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('paymentReference: $paymentReference, ')
          ..write('customerId: $customerId, ')
          ..write('cashierId: $cashierId, ')
          ..write('branchId: $branchId, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('isSynced: $isSynced, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      receiptNumber,
      subtotal,
      discount,
      tax,
      total,
      paymentMethod,
      paymentReference,
      customerId,
      cashierId,
      branchId,
      notes,
      status,
      createdAt,
      isSynced,
      syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingSale &&
          other.id == this.id &&
          other.receiptNumber == this.receiptNumber &&
          other.subtotal == this.subtotal &&
          other.discount == this.discount &&
          other.tax == this.tax &&
          other.total == this.total &&
          other.paymentMethod == this.paymentMethod &&
          other.paymentReference == this.paymentReference &&
          other.customerId == this.customerId &&
          other.cashierId == this.cashierId &&
          other.branchId == this.branchId &&
          other.notes == this.notes &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.isSynced == this.isSynced &&
          other.syncedAt == this.syncedAt);
}

class PendingSalesCompanion extends UpdateCompanion<PendingSale> {
  final Value<String> id;
  final Value<String> receiptNumber;
  final Value<double> subtotal;
  final Value<double> discount;
  final Value<double> tax;
  final Value<double> total;
  final Value<String> paymentMethod;
  final Value<String?> paymentReference;
  final Value<String?> customerId;
  final Value<String> cashierId;
  final Value<String> branchId;
  final Value<String?> notes;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<bool> isSynced;
  final Value<DateTime?> syncedAt;
  final Value<int> rowid;
  const PendingSalesCompanion({
    this.id = const Value.absent(),
    this.receiptNumber = const Value.absent(),
    this.subtotal = const Value.absent(),
    this.discount = const Value.absent(),
    this.tax = const Value.absent(),
    this.total = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.paymentReference = const Value.absent(),
    this.customerId = const Value.absent(),
    this.cashierId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingSalesCompanion.insert({
    required String id,
    required String receiptNumber,
    required double subtotal,
    this.discount = const Value.absent(),
    this.tax = const Value.absent(),
    required double total,
    required String paymentMethod,
    this.paymentReference = const Value.absent(),
    this.customerId = const Value.absent(),
    required String cashierId,
    required String branchId,
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    required DateTime createdAt,
    this.isSynced = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        receiptNumber = Value(receiptNumber),
        subtotal = Value(subtotal),
        total = Value(total),
        paymentMethod = Value(paymentMethod),
        cashierId = Value(cashierId),
        branchId = Value(branchId),
        createdAt = Value(createdAt);
  static Insertable<PendingSale> custom({
    Expression<String>? id,
    Expression<String>? receiptNumber,
    Expression<double>? subtotal,
    Expression<double>? discount,
    Expression<double>? tax,
    Expression<double>? total,
    Expression<String>? paymentMethod,
    Expression<String>? paymentReference,
    Expression<String>? customerId,
    Expression<String>? cashierId,
    Expression<String>? branchId,
    Expression<String>? notes,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<bool>? isSynced,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (receiptNumber != null) 'receipt_number': receiptNumber,
      if (subtotal != null) 'subtotal': subtotal,
      if (discount != null) 'discount': discount,
      if (tax != null) 'tax': tax,
      if (total != null) 'total': total,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (paymentReference != null) 'payment_reference': paymentReference,
      if (customerId != null) 'customer_id': customerId,
      if (cashierId != null) 'cashier_id': cashierId,
      if (branchId != null) 'branch_id': branchId,
      if (notes != null) 'notes': notes,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (isSynced != null) 'is_synced': isSynced,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingSalesCompanion copyWith(
      {Value<String>? id,
      Value<String>? receiptNumber,
      Value<double>? subtotal,
      Value<double>? discount,
      Value<double>? tax,
      Value<double>? total,
      Value<String>? paymentMethod,
      Value<String?>? paymentReference,
      Value<String?>? customerId,
      Value<String>? cashierId,
      Value<String>? branchId,
      Value<String?>? notes,
      Value<String>? status,
      Value<DateTime>? createdAt,
      Value<bool>? isSynced,
      Value<DateTime?>? syncedAt,
      Value<int>? rowid}) {
    return PendingSalesCompanion(
      id: id ?? this.id,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      subtotal: subtotal ?? this.subtotal,
      discount: discount ?? this.discount,
      tax: tax ?? this.tax,
      total: total ?? this.total,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentReference: paymentReference ?? this.paymentReference,
      customerId: customerId ?? this.customerId,
      cashierId: cashierId ?? this.cashierId,
      branchId: branchId ?? this.branchId,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      isSynced: isSynced ?? this.isSynced,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (receiptNumber.present) {
      map['receipt_number'] = Variable<String>(receiptNumber.value);
    }
    if (subtotal.present) {
      map['subtotal'] = Variable<double>(subtotal.value);
    }
    if (discount.present) {
      map['discount'] = Variable<double>(discount.value);
    }
    if (tax.present) {
      map['tax'] = Variable<double>(tax.value);
    }
    if (total.present) {
      map['total'] = Variable<double>(total.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (paymentReference.present) {
      map['payment_reference'] = Variable<String>(paymentReference.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (cashierId.present) {
      map['cashier_id'] = Variable<String>(cashierId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (isSynced.present) {
      map['is_synced'] = Variable<bool>(isSynced.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingSalesCompanion(')
          ..write('id: $id, ')
          ..write('receiptNumber: $receiptNumber, ')
          ..write('subtotal: $subtotal, ')
          ..write('discount: $discount, ')
          ..write('tax: $tax, ')
          ..write('total: $total, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('paymentReference: $paymentReference, ')
          ..write('customerId: $customerId, ')
          ..write('cashierId: $cashierId, ')
          ..write('branchId: $branchId, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('isSynced: $isSynced, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingSaleItemsTable extends PendingSaleItems
    with TableInfo<$PendingSaleItemsTable, PendingSaleItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingSaleItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _saleIdMeta = const VerificationMeta('saleId');
  @override
  late final GeneratedColumn<String> saleId = GeneratedColumn<String>(
      'sale_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productNameMeta =
      const VerificationMeta('productName');
  @override
  late final GeneratedColumn<String> productName = GeneratedColumn<String>(
      'product_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _skuMeta = const VerificationMeta('sku');
  @override
  late final GeneratedColumn<String> sku = GeneratedColumn<String>(
      'sku', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _quantityMeta =
      const VerificationMeta('quantity');
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
      'quantity', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _unitPriceMeta =
      const VerificationMeta('unitPrice');
  @override
  late final GeneratedColumn<double> unitPrice = GeneratedColumn<double>(
      'unit_price', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _discountMeta =
      const VerificationMeta('discount');
  @override
  late final GeneratedColumn<double> discount = GeneratedColumn<double>(
      'discount', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _totalMeta = const VerificationMeta('total');
  @override
  late final GeneratedColumn<double> total = GeneratedColumn<double>(
      'total', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        saleId,
        productId,
        productName,
        sku,
        quantity,
        unitPrice,
        discount,
        total
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_sale_items';
  @override
  VerificationContext validateIntegrity(Insertable<PendingSaleItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sale_id')) {
      context.handle(_saleIdMeta,
          saleId.isAcceptableOrUnknown(data['sale_id']!, _saleIdMeta));
    } else if (isInserting) {
      context.missing(_saleIdMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('product_name')) {
      context.handle(
          _productNameMeta,
          productName.isAcceptableOrUnknown(
              data['product_name']!, _productNameMeta));
    } else if (isInserting) {
      context.missing(_productNameMeta);
    }
    if (data.containsKey('sku')) {
      context.handle(
          _skuMeta, sku.isAcceptableOrUnknown(data['sku']!, _skuMeta));
    } else if (isInserting) {
      context.missing(_skuMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(_quantityMeta,
          quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta));
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('unit_price')) {
      context.handle(_unitPriceMeta,
          unitPrice.isAcceptableOrUnknown(data['unit_price']!, _unitPriceMeta));
    } else if (isInserting) {
      context.missing(_unitPriceMeta);
    }
    if (data.containsKey('discount')) {
      context.handle(_discountMeta,
          discount.isAcceptableOrUnknown(data['discount']!, _discountMeta));
    }
    if (data.containsKey('total')) {
      context.handle(
          _totalMeta, total.isAcceptableOrUnknown(data['total']!, _totalMeta));
    } else if (isInserting) {
      context.missing(_totalMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingSaleItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingSaleItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      saleId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sale_id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      productName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_name'])!,
      sku: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sku'])!,
      quantity: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}quantity'])!,
      unitPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}unit_price'])!,
      discount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}discount'])!,
      total: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}total'])!,
    );
  }

  @override
  $PendingSaleItemsTable createAlias(String alias) {
    return $PendingSaleItemsTable(attachedDatabase, alias);
  }
}

class PendingSaleItem extends DataClass implements Insertable<PendingSaleItem> {
  final int id;
  final String saleId;
  final String productId;
  final String productName;
  final String sku;
  final int quantity;
  final double unitPrice;
  final double discount;
  final double total;
  const PendingSaleItem(
      {required this.id,
      required this.saleId,
      required this.productId,
      required this.productName,
      required this.sku,
      required this.quantity,
      required this.unitPrice,
      required this.discount,
      required this.total});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['sale_id'] = Variable<String>(saleId);
    map['product_id'] = Variable<String>(productId);
    map['product_name'] = Variable<String>(productName);
    map['sku'] = Variable<String>(sku);
    map['quantity'] = Variable<int>(quantity);
    map['unit_price'] = Variable<double>(unitPrice);
    map['discount'] = Variable<double>(discount);
    map['total'] = Variable<double>(total);
    return map;
  }

  PendingSaleItemsCompanion toCompanion(bool nullToAbsent) {
    return PendingSaleItemsCompanion(
      id: Value(id),
      saleId: Value(saleId),
      productId: Value(productId),
      productName: Value(productName),
      sku: Value(sku),
      quantity: Value(quantity),
      unitPrice: Value(unitPrice),
      discount: Value(discount),
      total: Value(total),
    );
  }

  factory PendingSaleItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingSaleItem(
      id: serializer.fromJson<int>(json['id']),
      saleId: serializer.fromJson<String>(json['saleId']),
      productId: serializer.fromJson<String>(json['productId']),
      productName: serializer.fromJson<String>(json['productName']),
      sku: serializer.fromJson<String>(json['sku']),
      quantity: serializer.fromJson<int>(json['quantity']),
      unitPrice: serializer.fromJson<double>(json['unitPrice']),
      discount: serializer.fromJson<double>(json['discount']),
      total: serializer.fromJson<double>(json['total']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'saleId': serializer.toJson<String>(saleId),
      'productId': serializer.toJson<String>(productId),
      'productName': serializer.toJson<String>(productName),
      'sku': serializer.toJson<String>(sku),
      'quantity': serializer.toJson<int>(quantity),
      'unitPrice': serializer.toJson<double>(unitPrice),
      'discount': serializer.toJson<double>(discount),
      'total': serializer.toJson<double>(total),
    };
  }

  PendingSaleItem copyWith(
          {int? id,
          String? saleId,
          String? productId,
          String? productName,
          String? sku,
          int? quantity,
          double? unitPrice,
          double? discount,
          double? total}) =>
      PendingSaleItem(
        id: id ?? this.id,
        saleId: saleId ?? this.saleId,
        productId: productId ?? this.productId,
        productName: productName ?? this.productName,
        sku: sku ?? this.sku,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        discount: discount ?? this.discount,
        total: total ?? this.total,
      );
  PendingSaleItem copyWithCompanion(PendingSaleItemsCompanion data) {
    return PendingSaleItem(
      id: data.id.present ? data.id.value : this.id,
      saleId: data.saleId.present ? data.saleId.value : this.saleId,
      productId: data.productId.present ? data.productId.value : this.productId,
      productName:
          data.productName.present ? data.productName.value : this.productName,
      sku: data.sku.present ? data.sku.value : this.sku,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      unitPrice: data.unitPrice.present ? data.unitPrice.value : this.unitPrice,
      discount: data.discount.present ? data.discount.value : this.discount,
      total: data.total.present ? data.total.value : this.total,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingSaleItem(')
          ..write('id: $id, ')
          ..write('saleId: $saleId, ')
          ..write('productId: $productId, ')
          ..write('productName: $productName, ')
          ..write('sku: $sku, ')
          ..write('quantity: $quantity, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('discount: $discount, ')
          ..write('total: $total')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, saleId, productId, productName, sku,
      quantity, unitPrice, discount, total);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingSaleItem &&
          other.id == this.id &&
          other.saleId == this.saleId &&
          other.productId == this.productId &&
          other.productName == this.productName &&
          other.sku == this.sku &&
          other.quantity == this.quantity &&
          other.unitPrice == this.unitPrice &&
          other.discount == this.discount &&
          other.total == this.total);
}

class PendingSaleItemsCompanion extends UpdateCompanion<PendingSaleItem> {
  final Value<int> id;
  final Value<String> saleId;
  final Value<String> productId;
  final Value<String> productName;
  final Value<String> sku;
  final Value<int> quantity;
  final Value<double> unitPrice;
  final Value<double> discount;
  final Value<double> total;
  const PendingSaleItemsCompanion({
    this.id = const Value.absent(),
    this.saleId = const Value.absent(),
    this.productId = const Value.absent(),
    this.productName = const Value.absent(),
    this.sku = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unitPrice = const Value.absent(),
    this.discount = const Value.absent(),
    this.total = const Value.absent(),
  });
  PendingSaleItemsCompanion.insert({
    this.id = const Value.absent(),
    required String saleId,
    required String productId,
    required String productName,
    required String sku,
    required int quantity,
    required double unitPrice,
    this.discount = const Value.absent(),
    required double total,
  })  : saleId = Value(saleId),
        productId = Value(productId),
        productName = Value(productName),
        sku = Value(sku),
        quantity = Value(quantity),
        unitPrice = Value(unitPrice),
        total = Value(total);
  static Insertable<PendingSaleItem> custom({
    Expression<int>? id,
    Expression<String>? saleId,
    Expression<String>? productId,
    Expression<String>? productName,
    Expression<String>? sku,
    Expression<int>? quantity,
    Expression<double>? unitPrice,
    Expression<double>? discount,
    Expression<double>? total,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (saleId != null) 'sale_id': saleId,
      if (productId != null) 'product_id': productId,
      if (productName != null) 'product_name': productName,
      if (sku != null) 'sku': sku,
      if (quantity != null) 'quantity': quantity,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (discount != null) 'discount': discount,
      if (total != null) 'total': total,
    });
  }

  PendingSaleItemsCompanion copyWith(
      {Value<int>? id,
      Value<String>? saleId,
      Value<String>? productId,
      Value<String>? productName,
      Value<String>? sku,
      Value<int>? quantity,
      Value<double>? unitPrice,
      Value<double>? discount,
      Value<double>? total}) {
    return PendingSaleItemsCompanion(
      id: id ?? this.id,
      saleId: saleId ?? this.saleId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      sku: sku ?? this.sku,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discount: discount ?? this.discount,
      total: total ?? this.total,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (saleId.present) {
      map['sale_id'] = Variable<String>(saleId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (productName.present) {
      map['product_name'] = Variable<String>(productName.value);
    }
    if (sku.present) {
      map['sku'] = Variable<String>(sku.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (unitPrice.present) {
      map['unit_price'] = Variable<double>(unitPrice.value);
    }
    if (discount.present) {
      map['discount'] = Variable<double>(discount.value);
    }
    if (total.present) {
      map['total'] = Variable<double>(total.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingSaleItemsCompanion(')
          ..write('id: $id, ')
          ..write('saleId: $saleId, ')
          ..write('productId: $productId, ')
          ..write('productName: $productName, ')
          ..write('sku: $sku, ')
          ..write('quantity: $quantity, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('discount: $discount, ')
          ..write('total: $total')
          ..write(')'))
        .toString();
  }
}

class $SyncQueueTable extends SyncQueue
    with TableInfo<$SyncQueueTable, SyncQueueData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entityTableMeta =
      const VerificationMeta('entityTable');
  @override
  late final GeneratedColumn<String> entityTable = GeneratedColumn<String>(
      'entity_table', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordIdMeta =
      const VerificationMeta('recordId');
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
      'record_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
      'action', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _eventTypeMeta =
      const VerificationMeta('eventType');
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
      'event_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _deviceIdMeta =
      const VerificationMeta('deviceId');
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
      'device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _sequenceNumberMeta =
      const VerificationMeta('sequenceNumber');
  @override
  late final GeneratedColumn<int> sequenceNumber = GeneratedColumn<int>(
      'sequence_number', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _errorMessageMeta =
      const VerificationMeta('errorMessage');
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
      'error_message', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _retryCountMeta =
      const VerificationMeta('retryCount');
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
      'retry_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _maxRetriesMeta =
      const VerificationMeta('maxRetries');
  @override
  late final GeneratedColumn<int> maxRetries = GeneratedColumn<int>(
      'max_retries', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(3));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _lastAttemptAtMeta =
      const VerificationMeta('lastAttemptAt');
  @override
  late final GeneratedColumn<DateTime> lastAttemptAt =
      GeneratedColumn<DateTime>('last_attempt_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _syncedAtMeta =
      const VerificationMeta('syncedAt');
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
      'synced_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _serverIdMeta =
      const VerificationMeta('serverId');
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
      'server_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _serverTimestampMeta =
      const VerificationMeta('serverTimestamp');
  @override
  late final GeneratedColumn<DateTime> serverTimestamp =
      GeneratedColumn<DateTime>('server_timestamp', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        entityTable,
        recordId,
        action,
        eventType,
        payload,
        deviceId,
        userId,
        sequenceNumber,
        status,
        errorMessage,
        retryCount,
        maxRetries,
        createdAt,
        lastAttemptAt,
        syncedAt,
        serverId,
        serverTimestamp
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_queue';
  @override
  VerificationContext validateIntegrity(Insertable<SyncQueueData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entity_table')) {
      context.handle(
          _entityTableMeta,
          entityTable.isAcceptableOrUnknown(
              data['entity_table']!, _entityTableMeta));
    } else if (isInserting) {
      context.missing(_entityTableMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(_recordIdMeta,
          recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta));
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(_actionMeta,
          action.isAcceptableOrUnknown(data['action']!, _actionMeta));
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('event_type')) {
      context.handle(_eventTypeMeta,
          eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta));
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(_deviceIdMeta,
          deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta));
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    }
    if (data.containsKey('sequence_number')) {
      context.handle(
          _sequenceNumberMeta,
          sequenceNumber.isAcceptableOrUnknown(
              data['sequence_number']!, _sequenceNumberMeta));
    } else if (isInserting) {
      context.missing(_sequenceNumberMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('error_message')) {
      context.handle(
          _errorMessageMeta,
          errorMessage.isAcceptableOrUnknown(
              data['error_message']!, _errorMessageMeta));
    }
    if (data.containsKey('retry_count')) {
      context.handle(
          _retryCountMeta,
          retryCount.isAcceptableOrUnknown(
              data['retry_count']!, _retryCountMeta));
    }
    if (data.containsKey('max_retries')) {
      context.handle(
          _maxRetriesMeta,
          maxRetries.isAcceptableOrUnknown(
              data['max_retries']!, _maxRetriesMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
          _lastAttemptAtMeta,
          lastAttemptAt.isAcceptableOrUnknown(
              data['last_attempt_at']!, _lastAttemptAtMeta));
    }
    if (data.containsKey('synced_at')) {
      context.handle(_syncedAtMeta,
          syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta));
    }
    if (data.containsKey('server_id')) {
      context.handle(_serverIdMeta,
          serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta));
    }
    if (data.containsKey('server_timestamp')) {
      context.handle(
          _serverTimestampMeta,
          serverTimestamp.isAcceptableOrUnknown(
              data['server_timestamp']!, _serverTimestampMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncQueueData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncQueueData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      entityTable: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_table'])!,
      recordId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}record_id'])!,
      action: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}action'])!,
      eventType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}event_type'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      sequenceNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sequence_number'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      errorMessage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}error_message']),
      retryCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}retry_count'])!,
      maxRetries: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}max_retries'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      lastAttemptAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_attempt_at']),
      syncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}synced_at']),
      serverId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}server_id']),
      serverTimestamp: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}server_timestamp']),
    );
  }

  @override
  $SyncQueueTable createAlias(String alias) {
    return $SyncQueueTable(attachedDatabase, alias);
  }
}

class SyncQueueData extends DataClass implements Insertable<SyncQueueData> {
  final String id;
  final String entityTable;
  final String recordId;
  final String action;
  final String eventType;
  final String payload;
  final String deviceId;
  final String userId;
  final int sequenceNumber;
  final String status;
  final String? errorMessage;
  final int retryCount;
  final int maxRetries;
  final DateTime createdAt;
  final DateTime? lastAttemptAt;
  final DateTime? syncedAt;
  final String? serverId;
  final DateTime? serverTimestamp;
  const SyncQueueData(
      {required this.id,
      required this.entityTable,
      required this.recordId,
      required this.action,
      required this.eventType,
      required this.payload,
      required this.deviceId,
      required this.userId,
      required this.sequenceNumber,
      required this.status,
      this.errorMessage,
      required this.retryCount,
      required this.maxRetries,
      required this.createdAt,
      this.lastAttemptAt,
      this.syncedAt,
      this.serverId,
      this.serverTimestamp});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entity_table'] = Variable<String>(entityTable);
    map['record_id'] = Variable<String>(recordId);
    map['action'] = Variable<String>(action);
    map['event_type'] = Variable<String>(eventType);
    map['payload'] = Variable<String>(payload);
    map['device_id'] = Variable<String>(deviceId);
    map['user_id'] = Variable<String>(userId);
    map['sequence_number'] = Variable<int>(sequenceNumber);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    map['retry_count'] = Variable<int>(retryCount);
    map['max_retries'] = Variable<int>(maxRetries);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
    }
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    if (!nullToAbsent || serverTimestamp != null) {
      map['server_timestamp'] = Variable<DateTime>(serverTimestamp);
    }
    return map;
  }

  SyncQueueCompanion toCompanion(bool nullToAbsent) {
    return SyncQueueCompanion(
      id: Value(id),
      entityTable: Value(entityTable),
      recordId: Value(recordId),
      action: Value(action),
      eventType: Value(eventType),
      payload: Value(payload),
      deviceId: Value(deviceId),
      userId: Value(userId),
      sequenceNumber: Value(sequenceNumber),
      status: Value(status),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      retryCount: Value(retryCount),
      maxRetries: Value(maxRetries),
      createdAt: Value(createdAt),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      serverTimestamp: serverTimestamp == null && nullToAbsent
          ? const Value.absent()
          : Value(serverTimestamp),
    );
  }

  factory SyncQueueData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncQueueData(
      id: serializer.fromJson<String>(json['id']),
      entityTable: serializer.fromJson<String>(json['entityTable']),
      recordId: serializer.fromJson<String>(json['recordId']),
      action: serializer.fromJson<String>(json['action']),
      eventType: serializer.fromJson<String>(json['eventType']),
      payload: serializer.fromJson<String>(json['payload']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      userId: serializer.fromJson<String>(json['userId']),
      sequenceNumber: serializer.fromJson<int>(json['sequenceNumber']),
      status: serializer.fromJson<String>(json['status']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      maxRetries: serializer.fromJson<int>(json['maxRetries']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      serverTimestamp: serializer.fromJson<DateTime?>(json['serverTimestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entityTable': serializer.toJson<String>(entityTable),
      'recordId': serializer.toJson<String>(recordId),
      'action': serializer.toJson<String>(action),
      'eventType': serializer.toJson<String>(eventType),
      'payload': serializer.toJson<String>(payload),
      'deviceId': serializer.toJson<String>(deviceId),
      'userId': serializer.toJson<String>(userId),
      'sequenceNumber': serializer.toJson<int>(sequenceNumber),
      'status': serializer.toJson<String>(status),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'retryCount': serializer.toJson<int>(retryCount),
      'maxRetries': serializer.toJson<int>(maxRetries),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
      'serverId': serializer.toJson<String?>(serverId),
      'serverTimestamp': serializer.toJson<DateTime?>(serverTimestamp),
    };
  }

  SyncQueueData copyWith(
          {String? id,
          String? entityTable,
          String? recordId,
          String? action,
          String? eventType,
          String? payload,
          String? deviceId,
          String? userId,
          int? sequenceNumber,
          String? status,
          Value<String?> errorMessage = const Value.absent(),
          int? retryCount,
          int? maxRetries,
          DateTime? createdAt,
          Value<DateTime?> lastAttemptAt = const Value.absent(),
          Value<DateTime?> syncedAt = const Value.absent(),
          Value<String?> serverId = const Value.absent(),
          Value<DateTime?> serverTimestamp = const Value.absent()}) =>
      SyncQueueData(
        id: id ?? this.id,
        entityTable: entityTable ?? this.entityTable,
        recordId: recordId ?? this.recordId,
        action: action ?? this.action,
        eventType: eventType ?? this.eventType,
        payload: payload ?? this.payload,
        deviceId: deviceId ?? this.deviceId,
        userId: userId ?? this.userId,
        sequenceNumber: sequenceNumber ?? this.sequenceNumber,
        status: status ?? this.status,
        errorMessage:
            errorMessage.present ? errorMessage.value : this.errorMessage,
        retryCount: retryCount ?? this.retryCount,
        maxRetries: maxRetries ?? this.maxRetries,
        createdAt: createdAt ?? this.createdAt,
        lastAttemptAt:
            lastAttemptAt.present ? lastAttemptAt.value : this.lastAttemptAt,
        syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
        serverId: serverId.present ? serverId.value : this.serverId,
        serverTimestamp: serverTimestamp.present
            ? serverTimestamp.value
            : this.serverTimestamp,
      );
  SyncQueueData copyWithCompanion(SyncQueueCompanion data) {
    return SyncQueueData(
      id: data.id.present ? data.id.value : this.id,
      entityTable:
          data.entityTable.present ? data.entityTable.value : this.entityTable,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      action: data.action.present ? data.action.value : this.action,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      payload: data.payload.present ? data.payload.value : this.payload,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      userId: data.userId.present ? data.userId.value : this.userId,
      sequenceNumber: data.sequenceNumber.present
          ? data.sequenceNumber.value
          : this.sequenceNumber,
      status: data.status.present ? data.status.value : this.status,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      retryCount:
          data.retryCount.present ? data.retryCount.value : this.retryCount,
      maxRetries:
          data.maxRetries.present ? data.maxRetries.value : this.maxRetries,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      serverTimestamp: data.serverTimestamp.present
          ? data.serverTimestamp.value
          : this.serverTimestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueData(')
          ..write('id: $id, ')
          ..write('entityTable: $entityTable, ')
          ..write('recordId: $recordId, ')
          ..write('action: $action, ')
          ..write('eventType: $eventType, ')
          ..write('payload: $payload, ')
          ..write('deviceId: $deviceId, ')
          ..write('userId: $userId, ')
          ..write('sequenceNumber: $sequenceNumber, ')
          ..write('status: $status, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('retryCount: $retryCount, ')
          ..write('maxRetries: $maxRetries, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('serverId: $serverId, ')
          ..write('serverTimestamp: $serverTimestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      entityTable,
      recordId,
      action,
      eventType,
      payload,
      deviceId,
      userId,
      sequenceNumber,
      status,
      errorMessage,
      retryCount,
      maxRetries,
      createdAt,
      lastAttemptAt,
      syncedAt,
      serverId,
      serverTimestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncQueueData &&
          other.id == this.id &&
          other.entityTable == this.entityTable &&
          other.recordId == this.recordId &&
          other.action == this.action &&
          other.eventType == this.eventType &&
          other.payload == this.payload &&
          other.deviceId == this.deviceId &&
          other.userId == this.userId &&
          other.sequenceNumber == this.sequenceNumber &&
          other.status == this.status &&
          other.errorMessage == this.errorMessage &&
          other.retryCount == this.retryCount &&
          other.maxRetries == this.maxRetries &&
          other.createdAt == this.createdAt &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.syncedAt == this.syncedAt &&
          other.serverId == this.serverId &&
          other.serverTimestamp == this.serverTimestamp);
}

class SyncQueueCompanion extends UpdateCompanion<SyncQueueData> {
  final Value<String> id;
  final Value<String> entityTable;
  final Value<String> recordId;
  final Value<String> action;
  final Value<String> eventType;
  final Value<String> payload;
  final Value<String> deviceId;
  final Value<String> userId;
  final Value<int> sequenceNumber;
  final Value<String> status;
  final Value<String?> errorMessage;
  final Value<int> retryCount;
  final Value<int> maxRetries;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastAttemptAt;
  final Value<DateTime?> syncedAt;
  final Value<String?> serverId;
  final Value<DateTime?> serverTimestamp;
  final Value<int> rowid;
  const SyncQueueCompanion({
    this.id = const Value.absent(),
    this.entityTable = const Value.absent(),
    this.recordId = const Value.absent(),
    this.action = const Value.absent(),
    this.eventType = const Value.absent(),
    this.payload = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.userId = const Value.absent(),
    this.sequenceNumber = const Value.absent(),
    this.status = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.maxRetries = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.serverId = const Value.absent(),
    this.serverTimestamp = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncQueueCompanion.insert({
    required String id,
    required String entityTable,
    required String recordId,
    required String action,
    required String eventType,
    required String payload,
    required String deviceId,
    this.userId = const Value.absent(),
    required int sequenceNumber,
    this.status = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.maxRetries = const Value.absent(),
    required DateTime createdAt,
    this.lastAttemptAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.serverId = const Value.absent(),
    this.serverTimestamp = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        entityTable = Value(entityTable),
        recordId = Value(recordId),
        action = Value(action),
        eventType = Value(eventType),
        payload = Value(payload),
        deviceId = Value(deviceId),
        sequenceNumber = Value(sequenceNumber),
        createdAt = Value(createdAt);
  static Insertable<SyncQueueData> custom({
    Expression<String>? id,
    Expression<String>? entityTable,
    Expression<String>? recordId,
    Expression<String>? action,
    Expression<String>? eventType,
    Expression<String>? payload,
    Expression<String>? deviceId,
    Expression<String>? userId,
    Expression<int>? sequenceNumber,
    Expression<String>? status,
    Expression<String>? errorMessage,
    Expression<int>? retryCount,
    Expression<int>? maxRetries,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastAttemptAt,
    Expression<DateTime>? syncedAt,
    Expression<String>? serverId,
    Expression<DateTime>? serverTimestamp,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityTable != null) 'entity_table': entityTable,
      if (recordId != null) 'record_id': recordId,
      if (action != null) 'action': action,
      if (eventType != null) 'event_type': eventType,
      if (payload != null) 'payload': payload,
      if (deviceId != null) 'device_id': deviceId,
      if (userId != null) 'user_id': userId,
      if (sequenceNumber != null) 'sequence_number': sequenceNumber,
      if (status != null) 'status': status,
      if (errorMessage != null) 'error_message': errorMessage,
      if (retryCount != null) 'retry_count': retryCount,
      if (maxRetries != null) 'max_retries': maxRetries,
      if (createdAt != null) 'created_at': createdAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (serverId != null) 'server_id': serverId,
      if (serverTimestamp != null) 'server_timestamp': serverTimestamp,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncQueueCompanion copyWith(
      {Value<String>? id,
      Value<String>? entityTable,
      Value<String>? recordId,
      Value<String>? action,
      Value<String>? eventType,
      Value<String>? payload,
      Value<String>? deviceId,
      Value<String>? userId,
      Value<int>? sequenceNumber,
      Value<String>? status,
      Value<String?>? errorMessage,
      Value<int>? retryCount,
      Value<int>? maxRetries,
      Value<DateTime>? createdAt,
      Value<DateTime?>? lastAttemptAt,
      Value<DateTime?>? syncedAt,
      Value<String?>? serverId,
      Value<DateTime?>? serverTimestamp,
      Value<int>? rowid}) {
    return SyncQueueCompanion(
      id: id ?? this.id,
      entityTable: entityTable ?? this.entityTable,
      recordId: recordId ?? this.recordId,
      action: action ?? this.action,
      eventType: eventType ?? this.eventType,
      payload: payload ?? this.payload,
      deviceId: deviceId ?? this.deviceId,
      userId: userId ?? this.userId,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries ?? this.maxRetries,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      syncedAt: syncedAt ?? this.syncedAt,
      serverId: serverId ?? this.serverId,
      serverTimestamp: serverTimestamp ?? this.serverTimestamp,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entityTable.present) {
      map['entity_table'] = Variable<String>(entityTable.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (sequenceNumber.present) {
      map['sequence_number'] = Variable<int>(sequenceNumber.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (maxRetries.present) {
      map['max_retries'] = Variable<int>(maxRetries.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (serverTimestamp.present) {
      map['server_timestamp'] = Variable<DateTime>(serverTimestamp.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueCompanion(')
          ..write('id: $id, ')
          ..write('entityTable: $entityTable, ')
          ..write('recordId: $recordId, ')
          ..write('action: $action, ')
          ..write('eventType: $eventType, ')
          ..write('payload: $payload, ')
          ..write('deviceId: $deviceId, ')
          ..write('userId: $userId, ')
          ..write('sequenceNumber: $sequenceNumber, ')
          ..write('status: $status, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('retryCount: $retryCount, ')
          ..write('maxRetries: $maxRetries, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('serverId: $serverId, ')
          ..write('serverTimestamp: $serverTimestamp, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FavoriteProductsTable extends FavoriteProducts
    with TableInfo<$FavoriteProductsTable, FavoriteProduct> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoriteProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _addedAtMeta =
      const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
      'added_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [productId, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorite_products';
  @override
  VerificationContext validateIntegrity(Insertable<FavoriteProduct> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta,
          addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {productId};
  @override
  FavoriteProduct map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteProduct(
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      addedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}added_at'])!,
    );
  }

  @override
  $FavoriteProductsTable createAlias(String alias) {
    return $FavoriteProductsTable(attachedDatabase, alias);
  }
}

class FavoriteProduct extends DataClass implements Insertable<FavoriteProduct> {
  final String productId;
  final DateTime addedAt;
  const FavoriteProduct({required this.productId, required this.addedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['product_id'] = Variable<String>(productId);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  FavoriteProductsCompanion toCompanion(bool nullToAbsent) {
    return FavoriteProductsCompanion(
      productId: Value(productId),
      addedAt: Value(addedAt),
    );
  }

  factory FavoriteProduct.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteProduct(
      productId: serializer.fromJson<String>(json['productId']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'productId': serializer.toJson<String>(productId),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  FavoriteProduct copyWith({String? productId, DateTime? addedAt}) =>
      FavoriteProduct(
        productId: productId ?? this.productId,
        addedAt: addedAt ?? this.addedAt,
      );
  FavoriteProduct copyWithCompanion(FavoriteProductsCompanion data) {
    return FavoriteProduct(
      productId: data.productId.present ? data.productId.value : this.productId,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteProduct(')
          ..write('productId: $productId, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(productId, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteProduct &&
          other.productId == this.productId &&
          other.addedAt == this.addedAt);
}

class FavoriteProductsCompanion extends UpdateCompanion<FavoriteProduct> {
  final Value<String> productId;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const FavoriteProductsCompanion({
    this.productId = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoriteProductsCompanion.insert({
    required String productId,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  })  : productId = Value(productId),
        addedAt = Value(addedAt);
  static Insertable<FavoriteProduct> custom({
    Expression<String>? productId,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (productId != null) 'product_id': productId,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoriteProductsCompanion copyWith(
      {Value<String>? productId, Value<DateTime>? addedAt, Value<int>? rowid}) {
    return FavoriteProductsCompanion(
      productId: productId ?? this.productId,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteProductsCompanion(')
          ..write('productId: $productId, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecentSearchesTable extends RecentSearches
    with TableInfo<$RecentSearchesTable, RecentSearche> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecentSearchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _queryMeta = const VerificationMeta('query');
  @override
  late final GeneratedColumn<String> query = GeneratedColumn<String>(
      'query', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _searchedAtMeta =
      const VerificationMeta('searchedAt');
  @override
  late final GeneratedColumn<DateTime> searchedAt = GeneratedColumn<DateTime>(
      'searched_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, query, searchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recent_searches';
  @override
  VerificationContext validateIntegrity(Insertable<RecentSearche> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('query')) {
      context.handle(
          _queryMeta, query.isAcceptableOrUnknown(data['query']!, _queryMeta));
    } else if (isInserting) {
      context.missing(_queryMeta);
    }
    if (data.containsKey('searched_at')) {
      context.handle(
          _searchedAtMeta,
          searchedAt.isAcceptableOrUnknown(
              data['searched_at']!, _searchedAtMeta));
    } else if (isInserting) {
      context.missing(_searchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecentSearche map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecentSearche(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      query: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}query'])!,
      searchedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}searched_at'])!,
    );
  }

  @override
  $RecentSearchesTable createAlias(String alias) {
    return $RecentSearchesTable(attachedDatabase, alias);
  }
}

class RecentSearche extends DataClass implements Insertable<RecentSearche> {
  final int id;
  final String query;
  final DateTime searchedAt;
  const RecentSearche(
      {required this.id, required this.query, required this.searchedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['query'] = Variable<String>(query);
    map['searched_at'] = Variable<DateTime>(searchedAt);
    return map;
  }

  RecentSearchesCompanion toCompanion(bool nullToAbsent) {
    return RecentSearchesCompanion(
      id: Value(id),
      query: Value(query),
      searchedAt: Value(searchedAt),
    );
  }

  factory RecentSearche.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecentSearche(
      id: serializer.fromJson<int>(json['id']),
      query: serializer.fromJson<String>(json['query']),
      searchedAt: serializer.fromJson<DateTime>(json['searchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'query': serializer.toJson<String>(query),
      'searchedAt': serializer.toJson<DateTime>(searchedAt),
    };
  }

  RecentSearche copyWith({int? id, String? query, DateTime? searchedAt}) =>
      RecentSearche(
        id: id ?? this.id,
        query: query ?? this.query,
        searchedAt: searchedAt ?? this.searchedAt,
      );
  RecentSearche copyWithCompanion(RecentSearchesCompanion data) {
    return RecentSearche(
      id: data.id.present ? data.id.value : this.id,
      query: data.query.present ? data.query.value : this.query,
      searchedAt:
          data.searchedAt.present ? data.searchedAt.value : this.searchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecentSearche(')
          ..write('id: $id, ')
          ..write('query: $query, ')
          ..write('searchedAt: $searchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, query, searchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecentSearche &&
          other.id == this.id &&
          other.query == this.query &&
          other.searchedAt == this.searchedAt);
}

class RecentSearchesCompanion extends UpdateCompanion<RecentSearche> {
  final Value<int> id;
  final Value<String> query;
  final Value<DateTime> searchedAt;
  const RecentSearchesCompanion({
    this.id = const Value.absent(),
    this.query = const Value.absent(),
    this.searchedAt = const Value.absent(),
  });
  RecentSearchesCompanion.insert({
    this.id = const Value.absent(),
    required String query,
    required DateTime searchedAt,
  })  : query = Value(query),
        searchedAt = Value(searchedAt);
  static Insertable<RecentSearche> custom({
    Expression<int>? id,
    Expression<String>? query,
    Expression<DateTime>? searchedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (query != null) 'query': query,
      if (searchedAt != null) 'searched_at': searchedAt,
    });
  }

  RecentSearchesCompanion copyWith(
      {Value<int>? id, Value<String>? query, Value<DateTime>? searchedAt}) {
    return RecentSearchesCompanion(
      id: id ?? this.id,
      query: query ?? this.query,
      searchedAt: searchedAt ?? this.searchedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (query.present) {
      map['query'] = Variable<String>(query.value);
    }
    if (searchedAt.present) {
      map['searched_at'] = Variable<DateTime>(searchedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecentSearchesCompanion(')
          ..write('id: $id, ')
          ..write('query: $query, ')
          ..write('searchedAt: $searchedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $ProductsTable products = $ProductsTable(this);
  late final $BranchPricesTable branchPrices = $BranchPricesTable(this);
  late final $LocalStockTable localStock = $LocalStockTable(this);
  late final $CartItemsTable cartItems = $CartItemsTable(this);
  late final $PendingSalesTable pendingSales = $PendingSalesTable(this);
  late final $PendingSaleItemsTable pendingSaleItems =
      $PendingSaleItemsTable(this);
  late final $SyncQueueTable syncQueue = $SyncQueueTable(this);
  late final $FavoriteProductsTable favoriteProducts =
      $FavoriteProductsTable(this);
  late final $RecentSearchesTable recentSearches = $RecentSearchesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        categories,
        products,
        branchPrices,
        localStock,
        cartItems,
        pendingSales,
        pendingSaleItems,
        syncQueue,
        favoriteProducts,
        recentSearches
      ];
}

typedef $$CategoriesTableCreateCompanionBuilder = CategoriesCompanion Function({
  required String id,
  required String name,
  Value<String?> description,
  Value<String?> parentId,
  Value<String?> imageUrl,
  Value<int> sortOrder,
  Value<bool> isActive,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$CategoriesTableUpdateCompanionBuilder = CategoriesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String?> description,
  Value<String?> parentId,
  Value<String?> imageUrl,
  Value<int> sortOrder,
  Value<bool> isActive,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parentId => $composableBuilder(
      column: $table.parentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parentId => $composableBuilder(
      column: $table.parentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CategoriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CategoriesTable,
    Category,
    $$CategoriesTableFilterComposer,
    $$CategoriesTableOrderingComposer,
    $$CategoriesTableAnnotationComposer,
    $$CategoriesTableCreateCompanionBuilder,
    $$CategoriesTableUpdateCompanionBuilder,
    (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
    Category,
    PrefetchHooks Function()> {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String?> parentId = const Value.absent(),
            Value<String?> imageUrl = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CategoriesCompanion(
            id: id,
            name: name,
            description: description,
            parentId: parentId,
            imageUrl: imageUrl,
            sortOrder: sortOrder,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<String?> description = const Value.absent(),
            Value<String?> parentId = const Value.absent(),
            Value<String?> imageUrl = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CategoriesCompanion.insert(
            id: id,
            name: name,
            description: description,
            parentId: parentId,
            imageUrl: imageUrl,
            sortOrder: sortOrder,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CategoriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CategoriesTable,
    Category,
    $$CategoriesTableFilterComposer,
    $$CategoriesTableOrderingComposer,
    $$CategoriesTableAnnotationComposer,
    $$CategoriesTableCreateCompanionBuilder,
    $$CategoriesTableUpdateCompanionBuilder,
    (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
    Category,
    PrefetchHooks Function()>;
typedef $$ProductsTableCreateCompanionBuilder = ProductsCompanion Function({
  required String id,
  required String sku,
  required String name,
  Value<String?> description,
  required String categoryId,
  required double price,
  Value<double?> costPrice,
  Value<String> unit,
  Value<String?> imageUrl,
  Value<bool> isActive,
  Value<bool> trackInventory,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$ProductsTableUpdateCompanionBuilder = ProductsCompanion Function({
  Value<String> id,
  Value<String> sku,
  Value<String> name,
  Value<String?> description,
  Value<String> categoryId,
  Value<double> price,
  Value<double?> costPrice,
  Value<String> unit,
  Value<String?> imageUrl,
  Value<bool> isActive,
  Value<bool> trackInventory,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$ProductsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sku => $composableBuilder(
      column: $table.sku, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get costPrice => $composableBuilder(
      column: $table.costPrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get unit => $composableBuilder(
      column: $table.unit, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get trackInventory => $composableBuilder(
      column: $table.trackInventory,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$ProductsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sku => $composableBuilder(
      column: $table.sku, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get costPrice => $composableBuilder(
      column: $table.costPrice, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get unit => $composableBuilder(
      column: $table.unit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get trackInventory => $composableBuilder(
      column: $table.trackInventory,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ProductsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sku =>
      $composableBuilder(column: $table.sku, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => column);

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<double> get costPrice =>
      $composableBuilder(column: $table.costPrice, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<bool> get trackInventory => $composableBuilder(
      column: $table.trackInventory, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ProductsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProductsTable,
    Product,
    $$ProductsTableFilterComposer,
    $$ProductsTableOrderingComposer,
    $$ProductsTableAnnotationComposer,
    $$ProductsTableCreateCompanionBuilder,
    $$ProductsTableUpdateCompanionBuilder,
    (Product, BaseReferences<_$AppDatabase, $ProductsTable, Product>),
    Product,
    PrefetchHooks Function()> {
  $$ProductsTableTableManager(_$AppDatabase db, $ProductsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> sku = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String> categoryId = const Value.absent(),
            Value<double> price = const Value.absent(),
            Value<double?> costPrice = const Value.absent(),
            Value<String> unit = const Value.absent(),
            Value<String?> imageUrl = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<bool> trackInventory = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductsCompanion(
            id: id,
            sku: sku,
            name: name,
            description: description,
            categoryId: categoryId,
            price: price,
            costPrice: costPrice,
            unit: unit,
            imageUrl: imageUrl,
            isActive: isActive,
            trackInventory: trackInventory,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String sku,
            required String name,
            Value<String?> description = const Value.absent(),
            required String categoryId,
            required double price,
            Value<double?> costPrice = const Value.absent(),
            Value<String> unit = const Value.absent(),
            Value<String?> imageUrl = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<bool> trackInventory = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductsCompanion.insert(
            id: id,
            sku: sku,
            name: name,
            description: description,
            categoryId: categoryId,
            price: price,
            costPrice: costPrice,
            unit: unit,
            imageUrl: imageUrl,
            isActive: isActive,
            trackInventory: trackInventory,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ProductsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ProductsTable,
    Product,
    $$ProductsTableFilterComposer,
    $$ProductsTableOrderingComposer,
    $$ProductsTableAnnotationComposer,
    $$ProductsTableCreateCompanionBuilder,
    $$ProductsTableUpdateCompanionBuilder,
    (Product, BaseReferences<_$AppDatabase, $ProductsTable, Product>),
    Product,
    PrefetchHooks Function()>;
typedef $$BranchPricesTableCreateCompanionBuilder = BranchPricesCompanion
    Function({
  required String id,
  required String productId,
  required String branchId,
  required double price,
  Value<DateTime?> effectiveFrom,
  Value<DateTime?> effectiveTo,
  Value<int> rowid,
});
typedef $$BranchPricesTableUpdateCompanionBuilder = BranchPricesCompanion
    Function({
  Value<String> id,
  Value<String> productId,
  Value<String> branchId,
  Value<double> price,
  Value<DateTime?> effectiveFrom,
  Value<DateTime?> effectiveTo,
  Value<int> rowid,
});

class $$BranchPricesTableFilterComposer
    extends Composer<_$AppDatabase, $BranchPricesTable> {
  $$BranchPricesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get branchId => $composableBuilder(
      column: $table.branchId, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get effectiveFrom => $composableBuilder(
      column: $table.effectiveFrom, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get effectiveTo => $composableBuilder(
      column: $table.effectiveTo, builder: (column) => ColumnFilters(column));
}

class $$BranchPricesTableOrderingComposer
    extends Composer<_$AppDatabase, $BranchPricesTable> {
  $$BranchPricesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get branchId => $composableBuilder(
      column: $table.branchId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get effectiveFrom => $composableBuilder(
      column: $table.effectiveFrom,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get effectiveTo => $composableBuilder(
      column: $table.effectiveTo, builder: (column) => ColumnOrderings(column));
}

class $$BranchPricesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BranchPricesTable> {
  $$BranchPricesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<DateTime> get effectiveFrom => $composableBuilder(
      column: $table.effectiveFrom, builder: (column) => column);

  GeneratedColumn<DateTime> get effectiveTo => $composableBuilder(
      column: $table.effectiveTo, builder: (column) => column);
}

class $$BranchPricesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $BranchPricesTable,
    BranchPrice,
    $$BranchPricesTableFilterComposer,
    $$BranchPricesTableOrderingComposer,
    $$BranchPricesTableAnnotationComposer,
    $$BranchPricesTableCreateCompanionBuilder,
    $$BranchPricesTableUpdateCompanionBuilder,
    (
      BranchPrice,
      BaseReferences<_$AppDatabase, $BranchPricesTable, BranchPrice>
    ),
    BranchPrice,
    PrefetchHooks Function()> {
  $$BranchPricesTableTableManager(_$AppDatabase db, $BranchPricesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BranchPricesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BranchPricesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BranchPricesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<String> branchId = const Value.absent(),
            Value<double> price = const Value.absent(),
            Value<DateTime?> effectiveFrom = const Value.absent(),
            Value<DateTime?> effectiveTo = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BranchPricesCompanion(
            id: id,
            productId: productId,
            branchId: branchId,
            price: price,
            effectiveFrom: effectiveFrom,
            effectiveTo: effectiveTo,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productId,
            required String branchId,
            required double price,
            Value<DateTime?> effectiveFrom = const Value.absent(),
            Value<DateTime?> effectiveTo = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BranchPricesCompanion.insert(
            id: id,
            productId: productId,
            branchId: branchId,
            price: price,
            effectiveFrom: effectiveFrom,
            effectiveTo: effectiveTo,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$BranchPricesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $BranchPricesTable,
    BranchPrice,
    $$BranchPricesTableFilterComposer,
    $$BranchPricesTableOrderingComposer,
    $$BranchPricesTableAnnotationComposer,
    $$BranchPricesTableCreateCompanionBuilder,
    $$BranchPricesTableUpdateCompanionBuilder,
    (
      BranchPrice,
      BaseReferences<_$AppDatabase, $BranchPricesTable, BranchPrice>
    ),
    BranchPrice,
    PrefetchHooks Function()>;
typedef $$LocalStockTableCreateCompanionBuilder = LocalStockCompanion Function({
  required String id,
  required String productId,
  required String branchId,
  required int quantity,
  Value<int> minQuantity,
  Value<int?> maxQuantity,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$LocalStockTableUpdateCompanionBuilder = LocalStockCompanion Function({
  Value<String> id,
  Value<String> productId,
  Value<String> branchId,
  Value<int> quantity,
  Value<int> minQuantity,
  Value<int?> maxQuantity,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$LocalStockTableFilterComposer
    extends Composer<_$AppDatabase, $LocalStockTable> {
  $$LocalStockTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get branchId => $composableBuilder(
      column: $table.branchId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get minQuantity => $composableBuilder(
      column: $table.minQuantity, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get maxQuantity => $composableBuilder(
      column: $table.maxQuantity, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$LocalStockTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalStockTable> {
  $$LocalStockTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get branchId => $composableBuilder(
      column: $table.branchId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get minQuantity => $composableBuilder(
      column: $table.minQuantity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get maxQuantity => $composableBuilder(
      column: $table.maxQuantity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalStockTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalStockTable> {
  $$LocalStockTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<int> get minQuantity => $composableBuilder(
      column: $table.minQuantity, builder: (column) => column);

  GeneratedColumn<int> get maxQuantity => $composableBuilder(
      column: $table.maxQuantity, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalStockTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LocalStockTable,
    LocalStockData,
    $$LocalStockTableFilterComposer,
    $$LocalStockTableOrderingComposer,
    $$LocalStockTableAnnotationComposer,
    $$LocalStockTableCreateCompanionBuilder,
    $$LocalStockTableUpdateCompanionBuilder,
    (
      LocalStockData,
      BaseReferences<_$AppDatabase, $LocalStockTable, LocalStockData>
    ),
    LocalStockData,
    PrefetchHooks Function()> {
  $$LocalStockTableTableManager(_$AppDatabase db, $LocalStockTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalStockTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalStockTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalStockTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<String> branchId = const Value.absent(),
            Value<int> quantity = const Value.absent(),
            Value<int> minQuantity = const Value.absent(),
            Value<int?> maxQuantity = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalStockCompanion(
            id: id,
            productId: productId,
            branchId: branchId,
            quantity: quantity,
            minQuantity: minQuantity,
            maxQuantity: maxQuantity,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productId,
            required String branchId,
            required int quantity,
            Value<int> minQuantity = const Value.absent(),
            Value<int?> maxQuantity = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalStockCompanion.insert(
            id: id,
            productId: productId,
            branchId: branchId,
            quantity: quantity,
            minQuantity: minQuantity,
            maxQuantity: maxQuantity,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalStockTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LocalStockTable,
    LocalStockData,
    $$LocalStockTableFilterComposer,
    $$LocalStockTableOrderingComposer,
    $$LocalStockTableAnnotationComposer,
    $$LocalStockTableCreateCompanionBuilder,
    $$LocalStockTableUpdateCompanionBuilder,
    (
      LocalStockData,
      BaseReferences<_$AppDatabase, $LocalStockTable, LocalStockData>
    ),
    LocalStockData,
    PrefetchHooks Function()>;
typedef $$CartItemsTableCreateCompanionBuilder = CartItemsCompanion Function({
  Value<int> id,
  required String productId,
  required String productName,
  required String sku,
  required int quantity,
  required double unitPrice,
  Value<double> discount,
  required double total,
  Value<String?> notes,
  required DateTime addedAt,
});
typedef $$CartItemsTableUpdateCompanionBuilder = CartItemsCompanion Function({
  Value<int> id,
  Value<String> productId,
  Value<String> productName,
  Value<String> sku,
  Value<int> quantity,
  Value<double> unitPrice,
  Value<double> discount,
  Value<double> total,
  Value<String?> notes,
  Value<DateTime> addedAt,
});

class $$CartItemsTableFilterComposer
    extends Composer<_$AppDatabase, $CartItemsTable> {
  $$CartItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productName => $composableBuilder(
      column: $table.productName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sku => $composableBuilder(
      column: $table.sku, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get unitPrice => $composableBuilder(
      column: $table.unitPrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get discount => $composableBuilder(
      column: $table.discount, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get total => $composableBuilder(
      column: $table.total, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnFilters(column));
}

class $$CartItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $CartItemsTable> {
  $$CartItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productName => $composableBuilder(
      column: $table.productName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sku => $composableBuilder(
      column: $table.sku, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get unitPrice => $composableBuilder(
      column: $table.unitPrice, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get discount => $composableBuilder(
      column: $table.discount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get total => $composableBuilder(
      column: $table.total, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnOrderings(column));
}

class $$CartItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CartItemsTable> {
  $$CartItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get productName => $composableBuilder(
      column: $table.productName, builder: (column) => column);

  GeneratedColumn<String> get sku =>
      $composableBuilder(column: $table.sku, builder: (column) => column);

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<double> get unitPrice =>
      $composableBuilder(column: $table.unitPrice, builder: (column) => column);

  GeneratedColumn<double> get discount =>
      $composableBuilder(column: $table.discount, builder: (column) => column);

  GeneratedColumn<double> get total =>
      $composableBuilder(column: $table.total, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$CartItemsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CartItemsTable,
    CartItem,
    $$CartItemsTableFilterComposer,
    $$CartItemsTableOrderingComposer,
    $$CartItemsTableAnnotationComposer,
    $$CartItemsTableCreateCompanionBuilder,
    $$CartItemsTableUpdateCompanionBuilder,
    (CartItem, BaseReferences<_$AppDatabase, $CartItemsTable, CartItem>),
    CartItem,
    PrefetchHooks Function()> {
  $$CartItemsTableTableManager(_$AppDatabase db, $CartItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CartItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CartItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CartItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<String> productName = const Value.absent(),
            Value<String> sku = const Value.absent(),
            Value<int> quantity = const Value.absent(),
            Value<double> unitPrice = const Value.absent(),
            Value<double> discount = const Value.absent(),
            Value<double> total = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<DateTime> addedAt = const Value.absent(),
          }) =>
              CartItemsCompanion(
            id: id,
            productId: productId,
            productName: productName,
            sku: sku,
            quantity: quantity,
            unitPrice: unitPrice,
            discount: discount,
            total: total,
            notes: notes,
            addedAt: addedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String productId,
            required String productName,
            required String sku,
            required int quantity,
            required double unitPrice,
            Value<double> discount = const Value.absent(),
            required double total,
            Value<String?> notes = const Value.absent(),
            required DateTime addedAt,
          }) =>
              CartItemsCompanion.insert(
            id: id,
            productId: productId,
            productName: productName,
            sku: sku,
            quantity: quantity,
            unitPrice: unitPrice,
            discount: discount,
            total: total,
            notes: notes,
            addedAt: addedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CartItemsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CartItemsTable,
    CartItem,
    $$CartItemsTableFilterComposer,
    $$CartItemsTableOrderingComposer,
    $$CartItemsTableAnnotationComposer,
    $$CartItemsTableCreateCompanionBuilder,
    $$CartItemsTableUpdateCompanionBuilder,
    (CartItem, BaseReferences<_$AppDatabase, $CartItemsTable, CartItem>),
    CartItem,
    PrefetchHooks Function()>;
typedef $$PendingSalesTableCreateCompanionBuilder = PendingSalesCompanion
    Function({
  required String id,
  required String receiptNumber,
  required double subtotal,
  Value<double> discount,
  Value<double> tax,
  required double total,
  required String paymentMethod,
  Value<String?> paymentReference,
  Value<String?> customerId,
  required String cashierId,
  required String branchId,
  Value<String?> notes,
  Value<String> status,
  required DateTime createdAt,
  Value<bool> isSynced,
  Value<DateTime?> syncedAt,
  Value<int> rowid,
});
typedef $$PendingSalesTableUpdateCompanionBuilder = PendingSalesCompanion
    Function({
  Value<String> id,
  Value<String> receiptNumber,
  Value<double> subtotal,
  Value<double> discount,
  Value<double> tax,
  Value<double> total,
  Value<String> paymentMethod,
  Value<String?> paymentReference,
  Value<String?> customerId,
  Value<String> cashierId,
  Value<String> branchId,
  Value<String?> notes,
  Value<String> status,
  Value<DateTime> createdAt,
  Value<bool> isSynced,
  Value<DateTime?> syncedAt,
  Value<int> rowid,
});

class $$PendingSalesTableFilterComposer
    extends Composer<_$AppDatabase, $PendingSalesTable> {
  $$PendingSalesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get receiptNumber => $composableBuilder(
      column: $table.receiptNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get subtotal => $composableBuilder(
      column: $table.subtotal, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get discount => $composableBuilder(
      column: $table.discount, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get tax => $composableBuilder(
      column: $table.tax, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get total => $composableBuilder(
      column: $table.total, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get paymentReference => $composableBuilder(
      column: $table.paymentReference,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get customerId => $composableBuilder(
      column: $table.customerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cashierId => $composableBuilder(
      column: $table.cashierId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get branchId => $composableBuilder(
      column: $table.branchId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSynced => $composableBuilder(
      column: $table.isSynced, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnFilters(column));
}

class $$PendingSalesTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingSalesTable> {
  $$PendingSalesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get receiptNumber => $composableBuilder(
      column: $table.receiptNumber,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get subtotal => $composableBuilder(
      column: $table.subtotal, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get discount => $composableBuilder(
      column: $table.discount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get tax => $composableBuilder(
      column: $table.tax, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get total => $composableBuilder(
      column: $table.total, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get paymentReference => $composableBuilder(
      column: $table.paymentReference,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get customerId => $composableBuilder(
      column: $table.customerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cashierId => $composableBuilder(
      column: $table.cashierId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get branchId => $composableBuilder(
      column: $table.branchId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSynced => $composableBuilder(
      column: $table.isSynced, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnOrderings(column));
}

class $$PendingSalesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingSalesTable> {
  $$PendingSalesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get receiptNumber => $composableBuilder(
      column: $table.receiptNumber, builder: (column) => column);

  GeneratedColumn<double> get subtotal =>
      $composableBuilder(column: $table.subtotal, builder: (column) => column);

  GeneratedColumn<double> get discount =>
      $composableBuilder(column: $table.discount, builder: (column) => column);

  GeneratedColumn<double> get tax =>
      $composableBuilder(column: $table.tax, builder: (column) => column);

  GeneratedColumn<double> get total =>
      $composableBuilder(column: $table.total, builder: (column) => column);

  GeneratedColumn<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod, builder: (column) => column);

  GeneratedColumn<String> get paymentReference => $composableBuilder(
      column: $table.paymentReference, builder: (column) => column);

  GeneratedColumn<String> get customerId => $composableBuilder(
      column: $table.customerId, builder: (column) => column);

  GeneratedColumn<String> get cashierId =>
      $composableBuilder(column: $table.cashierId, builder: (column) => column);

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get isSynced =>
      $composableBuilder(column: $table.isSynced, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$PendingSalesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PendingSalesTable,
    PendingSale,
    $$PendingSalesTableFilterComposer,
    $$PendingSalesTableOrderingComposer,
    $$PendingSalesTableAnnotationComposer,
    $$PendingSalesTableCreateCompanionBuilder,
    $$PendingSalesTableUpdateCompanionBuilder,
    (
      PendingSale,
      BaseReferences<_$AppDatabase, $PendingSalesTable, PendingSale>
    ),
    PendingSale,
    PrefetchHooks Function()> {
  $$PendingSalesTableTableManager(_$AppDatabase db, $PendingSalesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingSalesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingSalesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingSalesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> receiptNumber = const Value.absent(),
            Value<double> subtotal = const Value.absent(),
            Value<double> discount = const Value.absent(),
            Value<double> tax = const Value.absent(),
            Value<double> total = const Value.absent(),
            Value<String> paymentMethod = const Value.absent(),
            Value<String?> paymentReference = const Value.absent(),
            Value<String?> customerId = const Value.absent(),
            Value<String> cashierId = const Value.absent(),
            Value<String> branchId = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<bool> isSynced = const Value.absent(),
            Value<DateTime?> syncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PendingSalesCompanion(
            id: id,
            receiptNumber: receiptNumber,
            subtotal: subtotal,
            discount: discount,
            tax: tax,
            total: total,
            paymentMethod: paymentMethod,
            paymentReference: paymentReference,
            customerId: customerId,
            cashierId: cashierId,
            branchId: branchId,
            notes: notes,
            status: status,
            createdAt: createdAt,
            isSynced: isSynced,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String receiptNumber,
            required double subtotal,
            Value<double> discount = const Value.absent(),
            Value<double> tax = const Value.absent(),
            required double total,
            required String paymentMethod,
            Value<String?> paymentReference = const Value.absent(),
            Value<String?> customerId = const Value.absent(),
            required String cashierId,
            required String branchId,
            Value<String?> notes = const Value.absent(),
            Value<String> status = const Value.absent(),
            required DateTime createdAt,
            Value<bool> isSynced = const Value.absent(),
            Value<DateTime?> syncedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PendingSalesCompanion.insert(
            id: id,
            receiptNumber: receiptNumber,
            subtotal: subtotal,
            discount: discount,
            tax: tax,
            total: total,
            paymentMethod: paymentMethod,
            paymentReference: paymentReference,
            customerId: customerId,
            cashierId: cashierId,
            branchId: branchId,
            notes: notes,
            status: status,
            createdAt: createdAt,
            isSynced: isSynced,
            syncedAt: syncedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PendingSalesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PendingSalesTable,
    PendingSale,
    $$PendingSalesTableFilterComposer,
    $$PendingSalesTableOrderingComposer,
    $$PendingSalesTableAnnotationComposer,
    $$PendingSalesTableCreateCompanionBuilder,
    $$PendingSalesTableUpdateCompanionBuilder,
    (
      PendingSale,
      BaseReferences<_$AppDatabase, $PendingSalesTable, PendingSale>
    ),
    PendingSale,
    PrefetchHooks Function()>;
typedef $$PendingSaleItemsTableCreateCompanionBuilder
    = PendingSaleItemsCompanion Function({
  Value<int> id,
  required String saleId,
  required String productId,
  required String productName,
  required String sku,
  required int quantity,
  required double unitPrice,
  Value<double> discount,
  required double total,
});
typedef $$PendingSaleItemsTableUpdateCompanionBuilder
    = PendingSaleItemsCompanion Function({
  Value<int> id,
  Value<String> saleId,
  Value<String> productId,
  Value<String> productName,
  Value<String> sku,
  Value<int> quantity,
  Value<double> unitPrice,
  Value<double> discount,
  Value<double> total,
});

class $$PendingSaleItemsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingSaleItemsTable> {
  $$PendingSaleItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get saleId => $composableBuilder(
      column: $table.saleId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productName => $composableBuilder(
      column: $table.productName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sku => $composableBuilder(
      column: $table.sku, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get unitPrice => $composableBuilder(
      column: $table.unitPrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get discount => $composableBuilder(
      column: $table.discount, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get total => $composableBuilder(
      column: $table.total, builder: (column) => ColumnFilters(column));
}

class $$PendingSaleItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingSaleItemsTable> {
  $$PendingSaleItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get saleId => $composableBuilder(
      column: $table.saleId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productName => $composableBuilder(
      column: $table.productName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sku => $composableBuilder(
      column: $table.sku, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get unitPrice => $composableBuilder(
      column: $table.unitPrice, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get discount => $composableBuilder(
      column: $table.discount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get total => $composableBuilder(
      column: $table.total, builder: (column) => ColumnOrderings(column));
}

class $$PendingSaleItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingSaleItemsTable> {
  $$PendingSaleItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get saleId =>
      $composableBuilder(column: $table.saleId, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get productName => $composableBuilder(
      column: $table.productName, builder: (column) => column);

  GeneratedColumn<String> get sku =>
      $composableBuilder(column: $table.sku, builder: (column) => column);

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<double> get unitPrice =>
      $composableBuilder(column: $table.unitPrice, builder: (column) => column);

  GeneratedColumn<double> get discount =>
      $composableBuilder(column: $table.discount, builder: (column) => column);

  GeneratedColumn<double> get total =>
      $composableBuilder(column: $table.total, builder: (column) => column);
}

class $$PendingSaleItemsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PendingSaleItemsTable,
    PendingSaleItem,
    $$PendingSaleItemsTableFilterComposer,
    $$PendingSaleItemsTableOrderingComposer,
    $$PendingSaleItemsTableAnnotationComposer,
    $$PendingSaleItemsTableCreateCompanionBuilder,
    $$PendingSaleItemsTableUpdateCompanionBuilder,
    (
      PendingSaleItem,
      BaseReferences<_$AppDatabase, $PendingSaleItemsTable, PendingSaleItem>
    ),
    PendingSaleItem,
    PrefetchHooks Function()> {
  $$PendingSaleItemsTableTableManager(
      _$AppDatabase db, $PendingSaleItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingSaleItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingSaleItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingSaleItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> saleId = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<String> productName = const Value.absent(),
            Value<String> sku = const Value.absent(),
            Value<int> quantity = const Value.absent(),
            Value<double> unitPrice = const Value.absent(),
            Value<double> discount = const Value.absent(),
            Value<double> total = const Value.absent(),
          }) =>
              PendingSaleItemsCompanion(
            id: id,
            saleId: saleId,
            productId: productId,
            productName: productName,
            sku: sku,
            quantity: quantity,
            unitPrice: unitPrice,
            discount: discount,
            total: total,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String saleId,
            required String productId,
            required String productName,
            required String sku,
            required int quantity,
            required double unitPrice,
            Value<double> discount = const Value.absent(),
            required double total,
          }) =>
              PendingSaleItemsCompanion.insert(
            id: id,
            saleId: saleId,
            productId: productId,
            productName: productName,
            sku: sku,
            quantity: quantity,
            unitPrice: unitPrice,
            discount: discount,
            total: total,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PendingSaleItemsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PendingSaleItemsTable,
    PendingSaleItem,
    $$PendingSaleItemsTableFilterComposer,
    $$PendingSaleItemsTableOrderingComposer,
    $$PendingSaleItemsTableAnnotationComposer,
    $$PendingSaleItemsTableCreateCompanionBuilder,
    $$PendingSaleItemsTableUpdateCompanionBuilder,
    (
      PendingSaleItem,
      BaseReferences<_$AppDatabase, $PendingSaleItemsTable, PendingSaleItem>
    ),
    PendingSaleItem,
    PrefetchHooks Function()>;
typedef $$SyncQueueTableCreateCompanionBuilder = SyncQueueCompanion Function({
  required String id,
  required String entityTable,
  required String recordId,
  required String action,
  required String eventType,
  required String payload,
  required String deviceId,
  Value<String> userId,
  required int sequenceNumber,
  Value<String> status,
  Value<String?> errorMessage,
  Value<int> retryCount,
  Value<int> maxRetries,
  required DateTime createdAt,
  Value<DateTime?> lastAttemptAt,
  Value<DateTime?> syncedAt,
  Value<String?> serverId,
  Value<DateTime?> serverTimestamp,
  Value<int> rowid,
});
typedef $$SyncQueueTableUpdateCompanionBuilder = SyncQueueCompanion Function({
  Value<String> id,
  Value<String> entityTable,
  Value<String> recordId,
  Value<String> action,
  Value<String> eventType,
  Value<String> payload,
  Value<String> deviceId,
  Value<String> userId,
  Value<int> sequenceNumber,
  Value<String> status,
  Value<String?> errorMessage,
  Value<int> retryCount,
  Value<int> maxRetries,
  Value<DateTime> createdAt,
  Value<DateTime?> lastAttemptAt,
  Value<DateTime?> syncedAt,
  Value<String?> serverId,
  Value<DateTime?> serverTimestamp,
  Value<int> rowid,
});

class $$SyncQueueTableFilterComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityTable => $composableBuilder(
      column: $table.entityTable, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get eventType => $composableBuilder(
      column: $table.eventType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sequenceNumber => $composableBuilder(
      column: $table.sequenceNumber,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get maxRetries => $composableBuilder(
      column: $table.maxRetries, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get serverTimestamp => $composableBuilder(
      column: $table.serverTimestamp,
      builder: (column) => ColumnFilters(column));
}

class $$SyncQueueTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityTable => $composableBuilder(
      column: $table.entityTable, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get eventType => $composableBuilder(
      column: $table.eventType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sequenceNumber => $composableBuilder(
      column: $table.sequenceNumber,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get maxRetries => $composableBuilder(
      column: $table.maxRetries, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get serverTimestamp => $composableBuilder(
      column: $table.serverTimestamp,
      builder: (column) => ColumnOrderings(column));
}

class $$SyncQueueTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityTable => $composableBuilder(
      column: $table.entityTable, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get sequenceNumber => $composableBuilder(
      column: $table.sequenceNumber, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => column);

  GeneratedColumn<int> get maxRetries => $composableBuilder(
      column: $table.maxRetries, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<DateTime> get serverTimestamp => $composableBuilder(
      column: $table.serverTimestamp, builder: (column) => column);
}

class $$SyncQueueTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncQueueTable,
    SyncQueueData,
    $$SyncQueueTableFilterComposer,
    $$SyncQueueTableOrderingComposer,
    $$SyncQueueTableAnnotationComposer,
    $$SyncQueueTableCreateCompanionBuilder,
    $$SyncQueueTableUpdateCompanionBuilder,
    (
      SyncQueueData,
      BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueData>
    ),
    SyncQueueData,
    PrefetchHooks Function()> {
  $$SyncQueueTableTableManager(_$AppDatabase db, $SyncQueueTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> entityTable = const Value.absent(),
            Value<String> recordId = const Value.absent(),
            Value<String> action = const Value.absent(),
            Value<String> eventType = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<String> deviceId = const Value.absent(),
            Value<String> userId = const Value.absent(),
            Value<int> sequenceNumber = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> errorMessage = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<int> maxRetries = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> lastAttemptAt = const Value.absent(),
            Value<DateTime?> syncedAt = const Value.absent(),
            Value<String?> serverId = const Value.absent(),
            Value<DateTime?> serverTimestamp = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncQueueCompanion(
            id: id,
            entityTable: entityTable,
            recordId: recordId,
            action: action,
            eventType: eventType,
            payload: payload,
            deviceId: deviceId,
            userId: userId,
            sequenceNumber: sequenceNumber,
            status: status,
            errorMessage: errorMessage,
            retryCount: retryCount,
            maxRetries: maxRetries,
            createdAt: createdAt,
            lastAttemptAt: lastAttemptAt,
            syncedAt: syncedAt,
            serverId: serverId,
            serverTimestamp: serverTimestamp,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String entityTable,
            required String recordId,
            required String action,
            required String eventType,
            required String payload,
            required String deviceId,
            Value<String> userId = const Value.absent(),
            required int sequenceNumber,
            Value<String> status = const Value.absent(),
            Value<String?> errorMessage = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<int> maxRetries = const Value.absent(),
            required DateTime createdAt,
            Value<DateTime?> lastAttemptAt = const Value.absent(),
            Value<DateTime?> syncedAt = const Value.absent(),
            Value<String?> serverId = const Value.absent(),
            Value<DateTime?> serverTimestamp = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncQueueCompanion.insert(
            id: id,
            entityTable: entityTable,
            recordId: recordId,
            action: action,
            eventType: eventType,
            payload: payload,
            deviceId: deviceId,
            userId: userId,
            sequenceNumber: sequenceNumber,
            status: status,
            errorMessage: errorMessage,
            retryCount: retryCount,
            maxRetries: maxRetries,
            createdAt: createdAt,
            lastAttemptAt: lastAttemptAt,
            syncedAt: syncedAt,
            serverId: serverId,
            serverTimestamp: serverTimestamp,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncQueueTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncQueueTable,
    SyncQueueData,
    $$SyncQueueTableFilterComposer,
    $$SyncQueueTableOrderingComposer,
    $$SyncQueueTableAnnotationComposer,
    $$SyncQueueTableCreateCompanionBuilder,
    $$SyncQueueTableUpdateCompanionBuilder,
    (
      SyncQueueData,
      BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueData>
    ),
    SyncQueueData,
    PrefetchHooks Function()>;
typedef $$FavoriteProductsTableCreateCompanionBuilder
    = FavoriteProductsCompanion Function({
  required String productId,
  required DateTime addedAt,
  Value<int> rowid,
});
typedef $$FavoriteProductsTableUpdateCompanionBuilder
    = FavoriteProductsCompanion Function({
  Value<String> productId,
  Value<DateTime> addedAt,
  Value<int> rowid,
});

class $$FavoriteProductsTableFilterComposer
    extends Composer<_$AppDatabase, $FavoriteProductsTable> {
  $$FavoriteProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnFilters(column));
}

class $$FavoriteProductsTableOrderingComposer
    extends Composer<_$AppDatabase, $FavoriteProductsTable> {
  $$FavoriteProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get productId => $composableBuilder(
      column: $table.productId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnOrderings(column));
}

class $$FavoriteProductsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FavoriteProductsTable> {
  $$FavoriteProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$FavoriteProductsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $FavoriteProductsTable,
    FavoriteProduct,
    $$FavoriteProductsTableFilterComposer,
    $$FavoriteProductsTableOrderingComposer,
    $$FavoriteProductsTableAnnotationComposer,
    $$FavoriteProductsTableCreateCompanionBuilder,
    $$FavoriteProductsTableUpdateCompanionBuilder,
    (
      FavoriteProduct,
      BaseReferences<_$AppDatabase, $FavoriteProductsTable, FavoriteProduct>
    ),
    FavoriteProduct,
    PrefetchHooks Function()> {
  $$FavoriteProductsTableTableManager(
      _$AppDatabase db, $FavoriteProductsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavoriteProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavoriteProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavoriteProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> productId = const Value.absent(),
            Value<DateTime> addedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              FavoriteProductsCompanion(
            productId: productId,
            addedAt: addedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String productId,
            required DateTime addedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              FavoriteProductsCompanion.insert(
            productId: productId,
            addedAt: addedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$FavoriteProductsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $FavoriteProductsTable,
    FavoriteProduct,
    $$FavoriteProductsTableFilterComposer,
    $$FavoriteProductsTableOrderingComposer,
    $$FavoriteProductsTableAnnotationComposer,
    $$FavoriteProductsTableCreateCompanionBuilder,
    $$FavoriteProductsTableUpdateCompanionBuilder,
    (
      FavoriteProduct,
      BaseReferences<_$AppDatabase, $FavoriteProductsTable, FavoriteProduct>
    ),
    FavoriteProduct,
    PrefetchHooks Function()>;
typedef $$RecentSearchesTableCreateCompanionBuilder = RecentSearchesCompanion
    Function({
  Value<int> id,
  required String query,
  required DateTime searchedAt,
});
typedef $$RecentSearchesTableUpdateCompanionBuilder = RecentSearchesCompanion
    Function({
  Value<int> id,
  Value<String> query,
  Value<DateTime> searchedAt,
});

class $$RecentSearchesTableFilterComposer
    extends Composer<_$AppDatabase, $RecentSearchesTable> {
  $$RecentSearchesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get query => $composableBuilder(
      column: $table.query, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get searchedAt => $composableBuilder(
      column: $table.searchedAt, builder: (column) => ColumnFilters(column));
}

class $$RecentSearchesTableOrderingComposer
    extends Composer<_$AppDatabase, $RecentSearchesTable> {
  $$RecentSearchesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get query => $composableBuilder(
      column: $table.query, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get searchedAt => $composableBuilder(
      column: $table.searchedAt, builder: (column) => ColumnOrderings(column));
}

class $$RecentSearchesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecentSearchesTable> {
  $$RecentSearchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get query =>
      $composableBuilder(column: $table.query, builder: (column) => column);

  GeneratedColumn<DateTime> get searchedAt => $composableBuilder(
      column: $table.searchedAt, builder: (column) => column);
}

class $$RecentSearchesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RecentSearchesTable,
    RecentSearche,
    $$RecentSearchesTableFilterComposer,
    $$RecentSearchesTableOrderingComposer,
    $$RecentSearchesTableAnnotationComposer,
    $$RecentSearchesTableCreateCompanionBuilder,
    $$RecentSearchesTableUpdateCompanionBuilder,
    (
      RecentSearche,
      BaseReferences<_$AppDatabase, $RecentSearchesTable, RecentSearche>
    ),
    RecentSearche,
    PrefetchHooks Function()> {
  $$RecentSearchesTableTableManager(
      _$AppDatabase db, $RecentSearchesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecentSearchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecentSearchesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecentSearchesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> query = const Value.absent(),
            Value<DateTime> searchedAt = const Value.absent(),
          }) =>
              RecentSearchesCompanion(
            id: id,
            query: query,
            searchedAt: searchedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String query,
            required DateTime searchedAt,
          }) =>
              RecentSearchesCompanion.insert(
            id: id,
            query: query,
            searchedAt: searchedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$RecentSearchesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RecentSearchesTable,
    RecentSearche,
    $$RecentSearchesTableFilterComposer,
    $$RecentSearchesTableOrderingComposer,
    $$RecentSearchesTableAnnotationComposer,
    $$RecentSearchesTableCreateCompanionBuilder,
    $$RecentSearchesTableUpdateCompanionBuilder,
    (
      RecentSearche,
      BaseReferences<_$AppDatabase, $RecentSearchesTable, RecentSearche>
    ),
    RecentSearche,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db, _db.products);
  $$BranchPricesTableTableManager get branchPrices =>
      $$BranchPricesTableTableManager(_db, _db.branchPrices);
  $$LocalStockTableTableManager get localStock =>
      $$LocalStockTableTableManager(_db, _db.localStock);
  $$CartItemsTableTableManager get cartItems =>
      $$CartItemsTableTableManager(_db, _db.cartItems);
  $$PendingSalesTableTableManager get pendingSales =>
      $$PendingSalesTableTableManager(_db, _db.pendingSales);
  $$PendingSaleItemsTableTableManager get pendingSaleItems =>
      $$PendingSaleItemsTableTableManager(_db, _db.pendingSaleItems);
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db, _db.syncQueue);
  $$FavoriteProductsTableTableManager get favoriteProducts =>
      $$FavoriteProductsTableTableManager(_db, _db.favoriteProducts);
  $$RecentSearchesTableTableManager get recentSearches =>
      $$RecentSearchesTableTableManager(_db, _db.recentSearches);
}
