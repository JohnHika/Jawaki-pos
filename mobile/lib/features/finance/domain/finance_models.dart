/// Immutable values returned by the Finance API and persisted in the local
/// non-sensitive Finance snapshot cache.
library;

class FinanceSnapshot {
  FinanceSnapshot({
    required this.branchId,
    required this.supplierPayablesOutstanding,
    required this.retailReceivablesOutstanding,
    required this.peerReceivablesOutstanding,
    List<FinancePayable> payables = const <FinancePayable>[],
    List<RetailReceivable> retailReceivables = const <RetailReceivable>[],
    List<PeerDebtor> peerDebtors = const <PeerDebtor>[],
    List<PeerReceivable> peerReceivables = const <PeerReceivable>[],
    this.savedAt,
  })  : payables = List<FinancePayable>.unmodifiable(payables),
        retailReceivables = List<RetailReceivable>.unmodifiable(retailReceivables),
        peerDebtors = List<PeerDebtor>.unmodifiable(peerDebtors),
        peerReceivables = List<PeerReceivable>.unmodifiable(peerReceivables);

  final String branchId;
  final double supplierPayablesOutstanding;
  final double retailReceivablesOutstanding;
  final double peerReceivablesOutstanding;
  final List<FinancePayable> payables;
  final List<RetailReceivable> retailReceivables;
  final List<PeerDebtor> peerDebtors;
  final List<PeerReceivable> peerReceivables;
  final DateTime? savedAt;

  factory FinanceSnapshot.fromJson(Map<String, dynamic> json) => FinanceSnapshot(
        branchId: _requiredString(json, 'branchId'),
        supplierPayablesOutstanding:
            _number(json['supplierPayablesOutstanding']),
        retailReceivablesOutstanding:
            _number(json['retailReceivablesOutstanding']),
        peerReceivablesOutstanding: _number(json['peerReceivablesOutstanding']),
        payables: _list(json['payables']).map(FinancePayable.fromJson).toList(),
        retailReceivables: _list(json['retailReceivables'])
            .map(RetailReceivable.fromJson)
            .toList(),
        peerDebtors: _list(json['peerDebtors']).map(PeerDebtor.fromJson).toList(),
        peerReceivables: _list(json['peerReceivables'])
            .map(PeerReceivable.fromJson)
            .toList(),
        savedAt: _date(json['savedAt']),
      );

  FinanceSnapshot copyWith({
    List<FinancePayable>? payables,
    List<RetailReceivable>? retailReceivables,
    List<PeerDebtor>? peerDebtors,
    List<PeerReceivable>? peerReceivables,
    DateTime? savedAt,
  }) =>
      FinanceSnapshot(
        branchId: branchId,
        supplierPayablesOutstanding: supplierPayablesOutstanding,
        retailReceivablesOutstanding: retailReceivablesOutstanding,
        peerReceivablesOutstanding: peerReceivablesOutstanding,
        payables: payables ?? this.payables,
        retailReceivables: retailReceivables ?? this.retailReceivables,
        peerDebtors: peerDebtors ?? this.peerDebtors,
        peerReceivables: peerReceivables ?? this.peerReceivables,
        savedAt: savedAt ?? this.savedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'branchId': branchId,
        'supplierPayablesOutstanding': supplierPayablesOutstanding,
        'retailReceivablesOutstanding': retailReceivablesOutstanding,
        'peerReceivablesOutstanding': peerReceivablesOutstanding,
        'payables': payables.map((value) => value.toJson()).toList(),
        'retailReceivables':
            retailReceivables.map((value) => value.toJson()).toList(),
        'peerDebtors': peerDebtors.map((value) => value.toJson()).toList(),
        'peerReceivables':
            peerReceivables.map((value) => value.toJson()).toList(),
        if (savedAt != null) 'savedAt': savedAt!.toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is FinanceSnapshot &&
      branchId == other.branchId &&
      supplierPayablesOutstanding == other.supplierPayablesOutstanding &&
      retailReceivablesOutstanding == other.retailReceivablesOutstanding &&
      peerReceivablesOutstanding == other.peerReceivablesOutstanding &&
      _sameList(payables, other.payables) &&
      _sameList(retailReceivables, other.retailReceivables) &&
      _sameList(peerDebtors, other.peerDebtors) &&
      _sameList(peerReceivables, other.peerReceivables) &&
      savedAt == other.savedAt;

  @override
  int get hashCode => Object.hash(
        branchId,
        supplierPayablesOutstanding,
        retailReceivablesOutstanding,
        peerReceivablesOutstanding,
        Object.hashAll(payables),
        Object.hashAll(retailReceivables),
        Object.hashAll(peerDebtors),
        Object.hashAll(peerReceivables),
        savedAt,
      );
}

class FinancePayable {
  const FinancePayable({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.supplierPhone,
    required this.invoiceNumber,
    required this.totalAmount,
    required this.paidAmount,
    required this.outstandingAmount,
    required this.dueDate,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String supplierId;
  final String supplierName;
  final String? supplierPhone;
  final String? invoiceNumber;
  final double totalAmount;
  final double paidAmount;
  final double outstandingAmount;
  final DateTime? dueDate;
  final String status;
  final DateTime? createdAt;

  factory FinancePayable.fromJson(Map<String, dynamic> json) {
    final supplier = _map(json['supplier']);
    return FinancePayable(
      id: _requiredString(json, 'id'),
      supplierId: _requiredString(supplier, 'id'),
      supplierName: _requiredString(supplier, 'name'),
      supplierPhone: _string(supplier['phone']),
      invoiceNumber: _string(json['invoiceNumber']),
      totalAmount: _number(json['totalAmount']),
      paidAmount: _number(json['paidAmount']),
      outstandingAmount: _number(json['outstandingAmount']),
      dueDate: _date(json['dueDate']),
      status: _requiredString(json, 'status'),
      createdAt: _date(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'supplier': <String, dynamic>{
          'id': supplierId,
          'name': supplierName,
          'phone': supplierPhone,
        },
        'invoiceNumber': invoiceNumber,
        'totalAmount': totalAmount,
        'paidAmount': paidAmount,
        'outstandingAmount': outstandingAmount,
        'dueDate': _dateJson(dueDate),
        'status': status,
        'createdAt': _dateJson(createdAt),
      };

  @override
  bool operator ==(Object other) => other is FinancePayable && toJson().toString() == other.toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;
}

class RetailReceivable {
  RetailReceivable({
    required this.id,
    required this.saleId,
    required this.receiptNumber,
    required this.customerId,
    required this.customerName,
    required this.originalAmount,
    required this.outstandingAmount,
    required this.dueDate,
    required this.status,
    required this.createdAt,
    required List<ReceivablePayment> payments,
  }) : payments = List<ReceivablePayment>.unmodifiable(payments);

  final String id;
  final String saleId;
  final String? receiptNumber;
  final String? customerId;
  final String? customerName;
  final double originalAmount;
  final double outstandingAmount;
  final DateTime? dueDate;
  final String status;
  final DateTime? createdAt;
  final List<ReceivablePayment> payments;

  factory RetailReceivable.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] == null ? null : _map(json['customer']);
    return RetailReceivable(
      id: _requiredString(json, 'id'),
      saleId: _requiredString(json, 'saleId'),
      receiptNumber: _string(json['receiptNumber']),
      customerId: customer == null ? null : _string(customer['id']),
      customerName: customer == null ? null : _string(customer['name']),
      originalAmount: _number(json['originalAmount']),
      outstandingAmount: _number(json['outstandingAmount']),
      dueDate: _date(json['dueDate']),
      status: _requiredString(json, 'status'),
      createdAt: _date(json['createdAt']),
      payments: _list(json['payments']).map(ReceivablePayment.fromJson).toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'saleId': saleId,
        'receiptNumber': receiptNumber,
        'customer': customerId == null && customerName == null
            ? null
            : <String, dynamic>{'id': customerId, 'name': customerName},
        'originalAmount': originalAmount,
        'outstandingAmount': outstandingAmount,
        'dueDate': _dateJson(dueDate),
        'status': status,
        'createdAt': _dateJson(createdAt),
        'payments': payments.map((value) => value.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      other is RetailReceivable && toJson().toString() == other.toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;
}

class PeerDebtor {
  const PeerDebtor({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.contactName,
    required this.phone,
    required this.email,
    required this.address,
    required this.notes,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String tenantId;
  final String name;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PeerDebtor.fromJson(Map<String, dynamic> json) => PeerDebtor(
        id: _requiredString(json, 'id'),
        tenantId: _requiredString(json, 'tenantId'),
        name: _requiredString(json, 'name'),
        contactName: _string(json['contactName']),
        phone: _string(json['phone']),
        email: _string(json['email']),
        address: _string(json['address']),
        notes: _string(json['notes']),
        isActive: json['isActive'] is bool ? json['isActive'] as bool : true,
        createdAt: _date(json['createdAt']),
        updatedAt: _date(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'tenantId': tenantId,
        'name': name,
        'contactName': contactName,
        'phone': phone,
        'email': email,
        'address': address,
        'notes': notes,
        'isActive': isActive,
        'createdAt': _dateJson(createdAt),
        'updatedAt': _dateJson(updatedAt),
      };

  @override
  bool operator ==(Object other) => other is PeerDebtor && toJson().toString() == other.toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;
}

class PeerReceivable {
  PeerReceivable({
    required this.id,
    required this.debtor,
    required this.reference,
    required this.description,
    required this.originalAmount,
    required this.outstandingAmount,
    required this.dueDate,
    required this.status,
    required this.createdAt,
    required List<ReceivablePayment> payments,
  }) : payments = List<ReceivablePayment>.unmodifiable(payments);

  final String id;
  final PeerDebtor debtor;
  final String? reference;
  final String description;
  final double originalAmount;
  final double outstandingAmount;
  final DateTime? dueDate;
  final String status;
  final DateTime? createdAt;
  final List<ReceivablePayment> payments;

  factory PeerReceivable.fromJson(Map<String, dynamic> json) => PeerReceivable(
        id: _requiredString(json, 'id'),
        debtor: PeerDebtor.fromJson(_map(json['debtor'])),
        reference: _string(json['reference']),
        description: _requiredString(json, 'description'),
        originalAmount: _number(json['originalAmount']),
        outstandingAmount: _number(json['outstandingAmount']),
        dueDate: _date(json['dueDate']),
        status: _requiredString(json, 'status'),
        createdAt: _date(json['createdAt']),
        payments: _list(json['payments']).map(ReceivablePayment.fromJson).toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'debtor': debtor.toJson(),
        'reference': reference,
        'description': description,
        'originalAmount': originalAmount,
        'outstandingAmount': outstandingAmount,
        'dueDate': _dateJson(dueDate),
        'status': status,
        'createdAt': _dateJson(createdAt),
        'payments': payments.map((value) => value.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) => other is PeerReceivable && toJson().toString() == other.toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;
}

class ReceivablePayment {
  const ReceivablePayment({
    required this.id,
    required this.receivableId,
    required this.amount,
    required this.method,
    required this.reference,
    required this.notes,
    required this.paidAt,
    required this.createdAt,
  });

  final String id;
  final String receivableId;
  final double amount;
  final String method;
  final String? reference;
  final String? notes;
  final DateTime? paidAt;
  final DateTime? createdAt;

  factory ReceivablePayment.fromJson(Map<String, dynamic> json) =>
      ReceivablePayment(
        id: _requiredString(json, 'id'),
        receivableId: _requiredString(json, 'receivableId'),
        amount: _number(json['amount']),
        method: _requiredString(json, 'method'),
        reference: _string(json['reference']),
        notes: _string(json['notes']),
        paidAt: _date(json['paidAt']),
        createdAt: _date(json['createdAt']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'receivableId': receivableId,
        'amount': amount,
        'method': method,
        'reference': reference,
        'notes': notes,
        'paidAt': _dateJson(paidAt),
        'createdAt': _dateJson(createdAt),
      };

  @override
  bool operator ==(Object other) =>
      other is ReceivablePayment && toJson().toString() == other.toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  throw FormatException('Expected an object, got ${value.runtimeType}.');
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value == null) return const <Map<String, dynamic>>[];
  if (value is! List) {
    throw FormatException('Expected a list, got ${value.runtimeType}.');
  }
  return value.map(_map).toList();
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Expected non-empty string for "$key".');
}

String? _string(Object? value) => value?.toString();

double _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Expected number, got ${value.runtimeType}.');
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException('Expected ISO-8601 date string.');
  }
  return DateTime.tryParse(value)?.toUtc() ??
      (throw FormatException('Invalid ISO-8601 date string: $value'));
}

String? _dateJson(DateTime? value) => value?.toUtc().toIso8601String();

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
