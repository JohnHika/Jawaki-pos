import 'package:drift/drift.dart' hide Column;

/// SQL helper for raw queries in the server routes.
///
/// Drift's [Variable] wrappers are not properly unwrapped by the sqlite3
/// delegate in the secure database configuration, so we use string
/// interpolation with proper escaping instead.
///
/// All queries are local (same-device SQLite), so SQL injection is not
/// a realistic threat vector. Escaping is still done for correctness.
class Sql {
  /// Escape and quote a string value.
  static String str(String s) => "'${s.replaceAll("'", "''")}'";

  /// Escape and quote an optional string value (NULL if null).
  static String opt(String? s) => s != null ? str(s) : 'NULL';

  /// A bare integer (no quotes needed).
  static String i(int n) => '$n';

  /// A bare numeric value (no quotes needed).
  static String numeric(num n) => '$n';

  /// Quote a DateTime as an ISO-8601 string.
  static String date(DateTime d) => str(d.toIso8601String());

  /// Format a boolean as '1' or '0'.
  static String flag(bool b) => b ? '1' : '0';

  /// Build a string of column assignments for UPDATE SET clauses from a map.
  /// Example: [assign({'name': 'John', 'age': 30})] → `"name = 'John', age = 30"`
  static String assign(Map<String, Object?> values) {
    return values.entries
        .map((e) {
          final v = e.value;
          if (v == null) return "${e.key} = NULL";
          if (v is String) return "${e.key} = ${str(v)}";
          if (v is int) return "${e.key} = $v";
          if (v is double) return "${e.key} = $v";
          if (v is bool) return "${e.key} = ${flag(v)}";
          if (v is DateTime) return "${e.key} = ${date(v)}";
          return "${e.key} = ${str(v.toString())}";
        })
        .join(', ');
  }

  /// Build a list of value expressions for INSERT.
  /// Example: [vals(['abc', 'John', 42])] → `'abc', 'John', 42`
  static String vals(List<Object?> vs) {
    return vs
        .map((v) {
          if (v == null) return 'NULL';
          if (v is String) return str(v);
          if (v is int) return '$v';
          if (v is double) return '$v';
          if (v is bool) return flag(v);
          if (v is DateTime) return date(v);
          return str(v.toString());
        })
        .join(', ');
  }
}
