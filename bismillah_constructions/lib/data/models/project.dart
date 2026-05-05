import '../../core/constants.dart';

class Project {
  final String id;
  final String name;
  final ProjectModel model;
  final ProjectStatus status;
  final DateTime createdAt;
  final String? customerId;
  final String? siteAddress;
  final double? budget;
  final String? projectManager;

  /// Service fee % for Labour-Rate model (e.g. 5 means 5% of total spend).
  final double? serviceFeePercent;

  /// 1 = archived (soft delete). Data preserved for legal evidence.
  final int isArchived;
  final DateTime? archivedAt;

  const Project({
    required this.id,
    required this.name,
    required this.model,
    required this.status,
    required this.createdAt,
    this.customerId,
    this.siteAddress,
    this.budget,
    this.projectManager,
    this.serviceFeePercent,
    this.isArchived = 0,
    this.archivedAt,
  });

  bool get archived => isArchived == 1;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'model': model.db,
        'status': status.db,
        'created_at': createdAt.toUtc().toIso8601String(),
        'customer_id': customerId,
        'site_address': siteAddress,
        'budget': budget,
        'project_manager': projectManager,
        'service_fee_percent': serviceFeePercent,
        'is_archived': isArchived,
        'archived_at': archivedAt?.toUtc().toIso8601String(),
      };

  factory Project.fromMap(Map<String, Object?> m) => Project(
        id: m['id'] as String,
        name: m['name'] as String,
        model: ProjectModelX.fromDb(m['model'] as String),
        status: ProjectStatusX.fromDb(m['status'] as String),
        createdAt: DateTime.parse(m['created_at'] as String),
        customerId: m['customer_id'] as String?,
        siteAddress: m['site_address'] as String?,
        budget: (m['budget'] as num?)?.toDouble(),
        projectManager: m['project_manager'] as String?,
        serviceFeePercent: (m['service_fee_percent'] as num?)?.toDouble(),
        isArchived: (m['is_archived'] as int?) ?? 0,
        archivedAt: m['archived_at'] == null
            ? null
            : DateTime.parse(m['archived_at'] as String),
      );

  Project copyWith({
    String? name,
    ProjectModel? model,
    ProjectStatus? status,
    String? customerId,
    String? siteAddress,
    double? budget,
    String? projectManager,
    double? serviceFeePercent,
    int? isArchived,
    DateTime? archivedAt,
  }) =>
      Project(
        id: id,
        name: name ?? this.name,
        model: model ?? this.model,
        status: status ?? this.status,
        createdAt: createdAt,
        customerId: customerId ?? this.customerId,
        siteAddress: siteAddress ?? this.siteAddress,
        budget: budget ?? this.budget,
        projectManager: projectManager ?? this.projectManager,
        serviceFeePercent: serviceFeePercent ?? this.serviceFeePercent,
        isArchived: isArchived ?? this.isArchived,
        archivedAt: archivedAt ?? this.archivedAt,
      );
}
