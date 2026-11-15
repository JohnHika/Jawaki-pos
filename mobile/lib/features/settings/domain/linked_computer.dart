/// A computer this account signed in by approving on a phone.
class LinkedComputer {
  const LinkedComputer({
    required this.id,
    required this.name,
    this.platform,
    this.place,
    this.linkedAt,
    this.lastActiveAt,
    this.isThisDevice = false,
  });

  final String id;
  final String name;

  /// `windows`, `macos`, `linux` or something the computer reported.
  final String? platform;

  /// City and country it signed in from, when known.
  final String? place;
  final DateTime? linkedAt;
  final DateTime? lastActiveAt;

  /// The device looking at this list is this very computer.
  final bool isThisDevice;

  factory LinkedComputer.fromJson(Map<String, dynamic> json) {
    String? text(Object? value) {
      final out = value?.toString().trim();
      return out == null || out.isEmpty ? null : out;
    }

    DateTime? when(Object? value) =>
        value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

    return LinkedComputer(
      id: json['id'].toString(),
      name: text(json['name']) ?? 'A computer',
      platform: text(json['platform']),
      place: text(json['place']),
      linkedAt: when(json['linkedAt']),
      lastActiveAt: when(json['lastActiveAt']),
      isThisDevice: json['isThisDevice'] == true,
    );
  }

  /// "Windows", "Mac" or "Linux"; other names pass through.
  String? get platformLabel => switch (platform) {
        null => null,
        'windows' => 'Windows',
        'macos' => 'Mac',
        'linux' => 'Linux',
        final other => other,
      };

  /// Seen in the last five minutes.
  bool activeNow({DateTime? now}) {
    final seen = lastActiveAt;
    if (seen == null) return false;
    return (now ?? DateTime.now()).difference(seen).inMinutes < 5;
  }
}
