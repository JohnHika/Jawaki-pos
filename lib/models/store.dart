class Store {
  final String id;
  final String name;
  final String? address;
  final String? aiStatus;
  final DateTime? aiExpiry;

  Store({
    required this.id,
    required this.name,
    this.address,
    this.aiStatus,
    this.aiExpiry,
  });

  factory Store.fromJson(Map<String, dynamic> json) {
    return Store(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      address: json['address'] as String?,
      aiStatus: json['ai_status'] as String? ?? json['aiStatus'] as String?,
      aiExpiry: json['ai_expiry'] != null
          ? DateTime.tryParse(json['ai_expiry'] as String)
          : json['aiExpiry'] != null
              ? DateTime.tryParse(json['aiExpiry'] as String)
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'ai_status': aiStatus,
      'ai_expiry': aiExpiry?.toIso8601String(),
    };
  }

  static List<Store> mockStores() {
    return [
      Store(
        id: 'store_001',
        name: 'Jawaki Branch - Nairobi',
        address: 'Kimathi Street, Nairobi',
        aiStatus: 'trial',
        aiExpiry: DateTime.now().add(const Duration(days: 5)),
      ),
      Store(
        id: 'store_002',
        name: 'Jawaki Branch - Mombasa',
        address: 'Moi Avenue, Mombasa',
        aiStatus: 'active',
        aiExpiry: DateTime.now().add(const Duration(days: 23)),
      ),
      Store(
        id: 'store_003',
        name: 'Jawaki Branch - Kisumu',
        address: 'Oginga Odinga Street, Kisumu',
        aiStatus: null,
        aiExpiry: null,
      ),
    ];
  }
}
