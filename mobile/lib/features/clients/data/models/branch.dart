import 'package:equatable/equatable.dart';

/// Branch Model - Represents a client's branch location
class Branch extends Equatable {
  final String id;
  final String clientId;
  final String name;
  final String? description;
  final String? address;
  final String? phone;
  final String? email;
  final bool isActive;
  final int deviceCount;
  final int activeDevices;
  final String? lastSync;
  final bool hasAi;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Branch({
    required this.id,
    required this.clientId,
    required this.name,
    this.description,
    this.address,
    this.phone,
    this.email,
    this.isActive = true,
    this.deviceCount = 0,
    this.activeDevices = 0,
    this.lastSync,
    this.hasAi = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Branch.fromJson(Map<String, dynamic> json) {
    return Branch(
      id: json['id'] as String,
      clientId: json['clientId'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      deviceCount: (json['deviceCount'] as num?)?.toInt() ?? 0,
      activeDevices: (json['activeDevices'] as num?)?.toInt() ?? 0,
      lastSync: json['lastSync'] as String?,
      hasAi: json['hasAi'] as bool? ?? false,
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
      'clientId': clientId,
      'name': name,
      'description': description,
      'address': address,
      'phone': phone,
      'email': email,
      'isActive': isActive,
      'deviceCount': deviceCount,
      'activeDevices': activeDevices,
      'lastSync': lastSync,
      'hasAi': hasAi,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Branch copyWith({
    String? id,
    String? clientId,
    String? name,
    String? description,
    String? address,
    String? phone,
    String? email,
    bool? isActive,
    int? deviceCount,
    int? activeDevices,
    String? lastSync,
    bool? hasAi,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Branch(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      name: name ?? this.name,
      description: description ?? this.description,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      isActive: isActive ?? this.isActive,
      deviceCount: deviceCount ?? this.deviceCount,
      activeDevices: activeDevices ?? this.activeDevices,
      lastSync: lastSync ?? this.lastSync,
      hasAi: hasAi ?? this.hasAi,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props {
    return [
      id,
      clientId,
      name,
      description,
      address,
      phone,
      email,
      isActive,
      deviceCount,
      activeDevices,
      lastSync,
      hasAi,
      createdAt,
      updatedAt,
    ];
  }
}
