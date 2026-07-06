class AiSubscription {
  final String id;
  final String storeId;
  final String status; // trial, active, expired, cancelled
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? trialEndDate;
  final bool autoRenew;

  AiSubscription({
    required this.id,
    required this.storeId,
    required this.status,
    this.startDate,
    this.endDate,
    this.trialEndDate,
    this.autoRenew = false,
  });

  factory AiSubscription.fromJson(Map<String, dynamic> json) {
    return AiSubscription(
      id: json['id'] as String? ?? '',
      storeId: json['store_id'] as String? ?? json['storeId'] as String? ?? '',
      status: json['status'] as String? ?? 'trial',
      startDate: json['start_date'] != null
          ? DateTime.tryParse(json['start_date'] as String)
          : json['startDate'] != null
              ? DateTime.tryParse(json['startDate'] as String)
              : null,
      endDate: json['end_date'] != null
          ? DateTime.tryParse(json['end_date'] as String)
          : json['endDate'] != null
              ? DateTime.tryParse(json['endDate'] as String)
              : null,
      trialEndDate: json['trial_end_date'] != null
          ? DateTime.tryParse(json['trial_end_date'] as String)
          : json['trialEndDate'] != null
              ? DateTime.tryParse(json['trialEndDate'] as String)
              : null,
      autoRenew: json['auto_renew'] as bool? ??
          json['autoRenew'] as bool? ??
          false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'store_id': storeId,
      'status': status,
      'start_date': startDate?.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'trial_end_date': trialEndDate?.toIso8601String(),
      'auto_renew': autoRenew,
    };
  }

  int get daysRemaining {
    if (status == 'trial' && trialEndDate != null) {
      return trialEndDate!.difference(DateTime.now()).inDays.clamp(0, 999);
    }
    if ((status == 'active' || status == 'trial') && endDate != null) {
      return endDate!.difference(DateTime.now()).inDays.clamp(0, 999);
    }
    return 0;
  }

  bool get isActive => status == 'active' || status == 'trial';
}
