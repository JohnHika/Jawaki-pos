import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/storage_service.dart';
import '../data/licence_service.dart';
import '../domain/licence_codec.dart';
import '../domain/licence_standing.dart';

/// What the Plan and licence screen and the Home banner show.
class LicenceView {
  const LicenceView({required this.standing, required this.claims});

  final LicenceStanding standing;

  /// The saved, checked licence, or null while the shop is still on trial.
  final LicenceClaims? claims;
}

LicenceService _defaultService() => LicenceService(getIt<StorageService>());

/// Builds the service. Tests replace this to use their own key and storage.
LicenceService Function() licenceServiceBuilder = _defaultService;

LicenceService licenceService() => licenceServiceBuilder();

/// True once Arche Axon's public key is set. Until then nothing about licences
/// is shown anywhere.
bool get licenceEnforced => licenceService().enforced;

/// The shop's standing, or null when licences are not enforced.
final licenceViewProvider = FutureProvider.autoDispose<LicenceView?>((ref) async {
  final service = licenceService();
  final standing = await service.refresh();
  if (standing == null) return null;
  return LicenceView(standing: standing, claims: await service.savedClaims());
});
