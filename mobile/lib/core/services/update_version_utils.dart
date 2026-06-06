String composeComparableVersion(String version, String buildNumber) {
  final normalizedVersion = version.trim();
  final normalizedBuild = buildNumber.trim();

  if (normalizedBuild.isEmpty) {
    return normalizedVersion;
  }

  return '$normalizedVersion+$normalizedBuild';
}

bool isNewerAppVersion(String latest, String current) {
  try {
    final latestParts = _parseComparableVersion(latest);
    final currentParts = _parseComparableVersion(current);
    final maxLength = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;

    while (latestParts.length < maxLength) {
      latestParts.add(0);
    }
    while (currentParts.length < maxLength) {
      currentParts.add(0);
    }

    for (int index = 0; index < maxLength; index += 1) {
      if (latestParts[index] > currentParts[index]) return true;
      if (latestParts[index] < currentParts[index]) return false;
    }

    return false;
  } catch (_) {
    return latest.compareTo(current) > 0;
  }
}

List<int> _parseComparableVersion(String value) {
  final normalizedValue = value.trim().replaceFirst(RegExp(r'^v'), '').replaceAll(RegExp(r'[+\-]'), '.');

  return normalizedValue
      .split('.')
      .where((segment) => segment.trim().isNotEmpty)
      .map((segment) => int.parse(segment.trim()))
      .toList();
}