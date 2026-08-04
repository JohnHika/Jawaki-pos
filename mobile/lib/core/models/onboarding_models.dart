/// Progress of a tenant's onboarding flow — which steps are done and
/// which are still pending.
class OnboardingProgress {
  final String id;
  final String tenantId;
  final Map<String, OnboardingStepStatus> steps;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OnboardingProgress({
    required this.id,
    required this.tenantId,
    required this.steps,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OnboardingProgress.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'] as Map<String, dynamic>? ?? {};
    return OnboardingProgress(
      id: json['id'] as String,
      tenantId: json['tenantId'] as String,
      steps: rawSteps.map(
        (key, value) => MapEntry(
          key,
          OnboardingStepStatus.fromJson(value as Map<String, dynamic>),
        ),
      ),
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

/// Status of a single onboarding step (e.g. "company_profile", "staff_invite").
class OnboardingStepStatus {
  final String status;
  final DateTime? completedAt;

  const OnboardingStepStatus({
    required this.status,
    this.completedAt,
  });

  factory OnboardingStepStatus.fromJson(Map<String, dynamic> json) {
    return OnboardingStepStatus(
      status: json['status'] as String,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
    );
  }
}

/// A staff invitation sent during tenant onboarding.
class StaffInvitation {
  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String roleId;
  final String? roleName;
  final String branchId;
  final String? branchName;
  final String status;
  final DateTime createdAt;

  const StaffInvitation({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.roleId,
    this.roleName,
    required this.branchId,
    this.branchName,
    required this.status,
    required this.createdAt,
  });

  factory StaffInvitation.fromJson(Map<String, dynamic> json) {
    return StaffInvitation(
      id: json['id'] as String,
      email: json['email'] as String,
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      roleId: json['roleId'] as String,
      roleName: json['roleName'] as String?,
      branchId: json['branchId'] as String,
      branchName: json['branchName'] as String?,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// A tenant-scoped role returned by GET /roles.
class Role {
  final String id;
  final String name;
  final String? description;
  final List<String> permissionKeys;
  final DateTime createdAt;

  const Role({
    required this.id,
    required this.name,
    this.description,
    required this.permissionKeys,
    required this.createdAt,
  });

  factory Role.fromJson(Map<String, dynamic> json) {
    return Role(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      permissionKeys: (json['permissionKeys'] as List<dynamic>?)
              ?.cast<String>() ??
          [],
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// A tenant-scoped branch returned by GET /branches.
class Branch {
  final String id;
  final String name;
  final String code;
  final String? address;
  final String? phone;
  final String? email;
  final bool isActive;
  final DateTime createdAt;

  const Branch({
    required this.id,
    required this.name,
    required this.code,
    this.address,
    this.phone,
    this.email,
    required this.isActive,
    required this.createdAt,
  });

  factory Branch.fromJson(Map<String, dynamic> json) {
    return Branch(
      id: json['id'] as String,
      name: json['name'] as String,
      code: json['code'] as String,
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
