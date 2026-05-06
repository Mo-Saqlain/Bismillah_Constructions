import 'dart:convert';

/// Unit-of-measure dimension class for a material category.
///
/// Drives how the material is priced/ordered:
///   * `disc` — discrete countable units (bricks, tiles, fittings) — usually
///     paired with `EA`. May carry physical dimensions in [MaterialTypeDef.dims].
///   * `surf` — surface area (tiles per SQFT, paint per gallon-per-SQFT).
///     [MaterialTypeDef.coverageRate] kicks in here.
///   * `vol`  — volume (concrete in CY, sand in m³).
///   * `wgt`  — weight (steel in LBS / KG, cement in BAG/KG).
enum UomType { disc, surf, vol, wgt }

extension UomTypeX on UomType {
  String get db => name;
  String get label => switch (this) {
        UomType.disc => 'Discrete',
        UomType.surf => 'Surface',
        UomType.vol => 'Volume',
        UomType.wgt => 'Weight',
      };
  String get short => switch (this) {
        UomType.disc => 'Disc',
        UomType.surf => 'Surf',
        UomType.vol => 'Vol',
        UomType.wgt => 'Wgt',
      };

  /// Suggested UOM strings for the picker. The user can still type any
  /// string they like — these are just defaults so the field isn't blank.
  List<String> get defaultUoms => switch (this) {
        UomType.disc => const ['EA', 'PCS'],
        UomType.surf => const ['SQFT', 'SQM'],
        UomType.vol => const ['CY', 'M3', 'L'],
        UomType.wgt => const ['LBS', 'KG', 'BAG', 'TON'],
      };

  static UomType? fromDb(String? s) {
    if (s == null) return null;
    return UomType.values
        .firstWhere((v) => v.name == s, orElse: () => UomType.disc);
  }
}

/// Length / Width / Height for [UomType.disc] items (e.g. a brick is
/// 9"×4.5"×3"). All three are optional — record only what's known.
class MaterialDims {
  final double? length;
  final double? width;
  final double? height;
  final String? unit; // free-form: "in", "cm", etc.

  const MaterialDims({this.length, this.width, this.height, this.unit});

  bool get isEmpty =>
      length == null && width == null && height == null && unit == null;

  Map<String, Object?> toJson() => {
        'l': length,
        'w': width,
        'h': height,
        'u': unit,
      };

  static MaterialDims? fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return MaterialDims(
        length: (m['l'] as num?)?.toDouble(),
        width: (m['w'] as num?)?.toDouble(),
        height: (m['h'] as num?)?.toDouble(),
        unit: m['u'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// User-managed material category. Built-in rows (the original five) cannot
/// be deleted but their label can be renamed; custom rows are fully editable.
///
/// v8 added procurement metadata (UOM, coverage rate, waste factor, lead
/// time, physical dims) so a single category can drive ordering math, not
/// just labelling.
class MaterialTypeDef {
  final String id;
  final String name;
  final bool isBuiltin;
  final int sortOrder;
  final UomType? uomType;

  /// Free-form unit string (EA / SQFT / CY / LBS / BAG / …). Not constrained
  /// to a fixed enum because every site has its own conventions.
  final String? uom;

  /// Units required per area, only meaningful for [UomType.surf]
  /// (e.g. 4 tiles / SQFT).
  final double? coverageRate;

  /// Default waste multiplier (e.g. 1.10 = order 10 % extra).
  final double? wasteFactor;

  /// Order-to-site buffer in days.
  final int? leadDays;

  /// L/W/H bundle for [UomType.disc] items.
  final MaterialDims? dims;

  final DateTime createdAt;

  const MaterialTypeDef({
    required this.id,
    required this.name,
    required this.isBuiltin,
    required this.sortOrder,
    required this.createdAt,
    this.uomType,
    this.uom,
    this.coverageRate,
    this.wasteFactor,
    this.leadDays,
    this.dims,
  });

  MaterialTypeDef copyWith({
    String? name,
    UomType? uomType,
    String? uom,
    double? coverageRate,
    double? wasteFactor,
    int? leadDays,
    MaterialDims? dims,
  }) =>
      MaterialTypeDef(
        id: id,
        name: name ?? this.name,
        isBuiltin: isBuiltin,
        sortOrder: sortOrder,
        createdAt: createdAt,
        uomType: uomType ?? this.uomType,
        uom: uom ?? this.uom,
        coverageRate: coverageRate ?? this.coverageRate,
        wasteFactor: wasteFactor ?? this.wasteFactor,
        leadDays: leadDays ?? this.leadDays,
        dims: dims ?? this.dims,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'is_builtin': isBuiltin ? 1 : 0,
        'sort_order': sortOrder,
        'uom_typ': uomType?.db,
        'uom': uom,
        'cov_rate': coverageRate,
        'waste_f': wasteFactor,
        'lead_d': leadDays,
        'dims':
            (dims == null || dims!.isEmpty) ? null : jsonEncode(dims!.toJson()),
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory MaterialTypeDef.fromMap(Map<String, Object?> m) => MaterialTypeDef(
        id: m['id'] as String,
        name: m['name'] as String,
        isBuiltin: ((m['is_builtin'] as num?)?.toInt() ?? 0) == 1,
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        uomType: UomTypeX.fromDb(m['uom_typ'] as String?),
        uom: m['uom'] as String?,
        coverageRate: (m['cov_rate'] as num?)?.toDouble(),
        wasteFactor: (m['waste_f'] as num?)?.toDouble(),
        leadDays: (m['lead_d'] as num?)?.toInt(),
        dims: MaterialDims.fromJson(m['dims'] as String?),
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
