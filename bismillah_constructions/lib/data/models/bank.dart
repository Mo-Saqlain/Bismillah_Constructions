class Bank {
  final String id;
  final String name;
  final String? accountNo;
  final DateTime createdAt;

  const Bank({
    required this.id,
    required this.name,
    this.accountNo,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'account_no': accountNo,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory Bank.fromMap(Map<String, Object?> m) => Bank(
        id: m['id'] as String,
        name: m['name'] as String,
        accountNo: m['account_no'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
