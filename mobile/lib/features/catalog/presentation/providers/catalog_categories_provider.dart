import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';

/// Live-updating list of product categories, shared by the products list,
/// category management sheet, and the add/edit product form.
final categoriesProvider = StreamProvider<List<Category>>((ref) {
  return getIt<AppDatabase>().watchAllCategories();
});
