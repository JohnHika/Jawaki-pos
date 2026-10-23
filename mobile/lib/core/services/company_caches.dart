/// Things the phone caches about one company (till rules, coupons) must not
/// outlive the sign-in: another shop may log in next on the same phone.
/// Each cache registers how to forget itself; sign-out calls [clearAll].
class CompanyCaches {
  CompanyCaches._();

  static final List<Future<void> Function()> _clearers = [];

  static void register(Future<void> Function() clear) {
    _clearers.add(clear);
  }

  static Future<void> clearAll() async {
    for (final clear in List.of(_clearers)) {
      try {
        await clear();
      } catch (_) {
        // Forgetting is best effort; the next sign-in refreshes anyway.
      }
    }
  }
}
