import '../../core/constants.dart';

class MaterialItem {
  final String id;
  final String projectId;
  final String supplierId;
  final String? transactionId;
  final MaterialType materialType;
  final MaterialUnit unit;
  final double quantity;
  final double rate;
  final double totalCost;
  final MaterialTxnType txnType;
  final DateTime createdAt;

  const MaterialItem({
    required this.id,
    required this.projectId,
    required this.supplierId,
    this.transactionId,
    required this.materialType,
    required this.unit,
    required this.quantity,
    required this.rate,
    required this.totalCost,
    required this.txnType,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'project_id': projectId,
        'supplier_id': supplierId,
        'transaction_id': transactionId,
        'material_type': materialType.db,
        'unit': unit.db,
        'quantity': quantity,
        'rate': rate,
        'total_cost': totalCost,
        'txn_type': txnType.db,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory MaterialItem.fromMap(Map<String, Object?> m) => MaterialItem(
        id: m['id'] as String,
        projectId: m['project_id'] as String,
        supplierId: m['supplier_id'] as String,
        transactionId: m['transaction_id'] as String?,
        materialType: MaterialTypeX.fromDb(m['material_type'] as String),
        unit: MaterialUnitX.fromDb(m['unit'] as String),
        quantity: (m['quantity'] as num).toDouble(),
        rate: (m['rate'] as num).toDouble(),
        totalCost: (m['total_cost'] as num).toDouble(),
        txnType: MaterialTxnTypeX.fromDb(m['txn_type'] as String),
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  /// Brick pricing: total = (quantity / 1000) * rate.
  /// All other materials: total = quantity * rate.
  static double computeTotal(
      MaterialType type, double quantity, double rate) {
    if (type == MaterialType.brick) return (quantity / 1000) * rate;
    return quantity * rate;
  }
}
