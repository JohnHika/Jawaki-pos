/// A payment taken outside the app (bank transfer, cheque…) that a manager
/// must approve before it counts.
class ManualPaymentRequest {
  const ManualPaymentRequest({
    required this.id,
    required this.requestNumber,
    required this.branchId,
    required this.paymentMethod,
    required this.amount,
    required this.reason,
    required this.status,
    required this.requestedById,
    required this.createdAt,
    this.saleId,
    this.receiptNumber,
    this.notes,
    this.rejectionReason,
    this.requestedBy,
    this.approvedBy,
  });

  final String id;
  final String requestNumber;
  final String branchId;
  final String? saleId;
  final String? receiptNumber;
  final String paymentMethod;
  final double amount;
  final String reason;
  final String? notes;
  final String status;
  final String? rejectionReason;
  final String? requestedBy;
  final String requestedById;
  final String? approvedBy;
  final DateTime? createdAt;

  bool get isPending => status == 'PENDING';
  bool get isRejected => status == 'REJECTED';

  /// Approved requests linked to a sale end up COMPLETED; both mean "accepted".
  bool get isAccepted => status == 'APPROVED' || status == 'COMPLETED';

  factory ManualPaymentRequest.fromJson(Map<String, dynamic> json) {
    String? str(Object? v) {
      final s = v?.toString().trim();
      return s == null || s.isEmpty ? null : s;
    }

    return ManualPaymentRequest(
      id: json['id'].toString(),
      requestNumber: json['requestNumber']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? '',
      saleId: str(json['saleId']),
      receiptNumber: str(json['receiptNumber']),
      paymentMethod: json['paymentMethod']?.toString() ?? '',
      amount: double.tryParse(json['amount']?.toString() ?? '') ?? 0,
      reason: json['reason']?.toString() ?? '',
      notes: str(json['notes']),
      status: json['status']?.toString() ?? 'PENDING',
      rejectionReason: str(json['rejectionReason']),
      requestedBy: str(json['requestedBy']),
      requestedById: json['requestedById']?.toString() ?? '',
      approvedBy: str(json['approvedBy']),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
    );
  }
}
