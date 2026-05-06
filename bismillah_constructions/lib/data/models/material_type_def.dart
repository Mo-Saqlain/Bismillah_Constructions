/// User-managed material category. Built-in rows (the original five) cannot
/// be deleted but their label can be renamed; custom rows are fully editable.
class MaterialTypeDef {
  final String id;
  final String name;
  final bool isBuiltin;
  final int sortOrder;
  final DateTime createdAt;

  const MaterialTypeDef({
    required this.id,
    required this.name,
    required this.isBuiltin,
    required this.sortOrder,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'is_builtin': isBuiltin ? 1 : 0,
        'sort_order': sortOrder,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory MaterialTypeDef.fromMap(Map<String, Object?> m) => MaterialTypeDef(
        id: m['id'] as String,
        name: m['name'] as String,
        isBuiltin: ((m['is_builtin'] as num?)?.toInt() ?? 0) == 1,
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
