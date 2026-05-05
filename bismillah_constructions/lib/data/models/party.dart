import '../../core/constants.dart';

/// A party — customer or supplier. Common fields shared; table-specific
/// fields (profile) are nullable and populated only from their own table.
class Party {
  final String id;
  final String name;
  final String? phone;
  final DateTime createdAt;

  // Customer profile fields
  final String? ntnCnic;
  final String? address;
  final double? creditLimit;

  // Supplier profile fields
  final SupplierCategory? category;
  final String? taxStatus;
  final String? bankDetails;

  const Party({
    required this.id,
    required this.name,
    this.phone,
    required this.createdAt,
    this.ntnCnic,
    this.address,
    this.creditLimit,
    this.category,
    this.taxStatus,
    this.bankDetails,
  });

  /// Map for INSERT into the `customers` table.
  Map<String, Object?> toCustomerMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'created_at': createdAt.toUtc().toIso8601String(),
        'ntn_cnic': ntnCnic,
        'address': address,
        'credit_limit': creditLimit,
      };

  /// Map for INSERT into the `suppliers` table.
  Map<String, Object?> toSupplierMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'created_at': createdAt.toUtc().toIso8601String(),
        'category': category?.db,
        'tax_status': taxStatus,
        'bank_details': bankDetails,
      };

  factory Party.fromMap(Map<String, Object?> m) => Party(
        id: m['id'] as String,
        name: m['name'] as String,
        phone: m['phone'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
        ntnCnic: m['ntn_cnic'] as String?,
        address: m['address'] as String?,
        creditLimit: (m['credit_limit'] as num?)?.toDouble(),
        category: m['category'] == null
            ? null
            : SupplierCategoryX.fromDb(m['category'] as String),
        taxStatus: m['tax_status'] as String?,
        bankDetails: m['bank_details'] as String?,
      );
}
