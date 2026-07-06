import 'package:equatable/equatable.dart';

/// POS Client Model - Represents a Levisa POS client (e.g., Levisa, TSL, Kate)
class PosClient extends Equatable {
  final String id;
  final String name;
  final String slug;
  final String? logoUrl;
  final bool isActive;
  final int branchCount;
  final int activeBranches;
  final String? subscriptionStatus;
  final DateTime? subscriptionExpiry;
  final double? pendingPayments;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PosClient({
    required this.id,
    required this.name,
    required this.slug,
    this.logoUrl,
    this.isActive = true,
    this.branchCount = 0,
    this.activeBranches = 0,
    this.subscriptionStatus,
    this.subscriptionExpiry,
    this.pendingPayments,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Check if client has issues (expired trial, pending payments)
  bool get hasIssues {
    if (subscriptionStatus == 'trial' && subscriptionExpiry != null) {
      return DateTime.now().isAfter(subscriptionExpiry!);
    }
    return pendingPayments != null && pendingPayments! > 0;
  }

  /// Check if subscription is active
  bool get isSubscriptionActive {
    if (subscriptionStatus == 'trial' && subscriptionExpiry != null) {
      return DateTime.now().isBefore(subscriptionExpiry!);
    }
    return subscriptionStatus == 'active';
  }

  factory PosClient.fromJson(Map<String, dynamic> json) {
    return PosClient(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      logoUrl: json['logoUrl'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      branchCount: (json['branchCount'] as num?)?.toInt() ?? 0,
      activeBranches: (json['activeBranches'] as num?)?.toInt() ?? 0,
      subscriptionStatus: json['subscriptionStatus'] as String?,
      subscriptionExpiry: json['subscriptionExpiry'] != null
          ? DateTime.parse(json['subscriptionExpiry'] as String)
          : null,
      pendingPayments: (json['pendingPayments'] as num?)?.toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'logoUrl': logoUrl,
      'isActive': isActive,
      'branchCount': branchCount,
      'activeBranches': activeBranches,
      'subscriptionStatus': subscriptionStatus,
      'subscriptionExpiry': subscriptionExpiry?.toIso8601String(),
      'pendingPayments': pendingPayments,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  PosClient copyWith({
    String? id,
    String? name,
    String? slug,
    String? logoUrl,
    bool? isActive,
    int? branchCount,
    int? activeBranches,
    String? subscriptionStatus,
    DateTime? subscriptionExpiry,
    double? pendingPayments,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PosClient(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      logoUrl: logoUrl ?? this.logoUrl,
      isActive: isActive ?? this.isActive,
      branchCount: branchCount ?? this.branchCount,
      activeBranches: activeBranches ?? this.activeBranches,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      subscriptionExpiry: subscriptionExpiry ?? this.subscriptionExpiry,
      pendingPayments: pendingPayments ?? this.pendingPayments,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props {
    return [
      id,
      name,
      slug,
      logoUrl,
      isActive,
      branchCount,
      activeBranches,
      subscriptionStatus,
      subscriptionExpiry,
      pendingPayments,
      createdAt,
      updatedAt,
    ];
  }
}
