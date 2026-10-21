/// Build-time configuration for ACA (Axon Counterbase Admin).
///
/// ACA has exactly one data source: the live Counterbase API, the same server
/// and database the Counterbase POS app uses. There is no demo mode, no sample
/// data and no in-app server switch.
///
/// The only way to point a build somewhere else is the compile-time define
/// `ACA_API_BASE_URL`, used by QA debug builds (applicationId suffix `.qa`).
/// A release build refuses to run against anything but production.
class AcaConfig {
  AcaConfig._();

  static const String productionApi = 'https://arche-axon-pos-api.onrender.com/api/v1';

  static const String apiBaseUrl = String.fromEnvironment(
    'ACA_API_BASE_URL',
    defaultValue: productionApi,
  );

  static bool get isProduction => apiBaseUrl == productionApi;

  /// Every platform-staff endpoint lives under this prefix.
  static String get platformBase => '$apiBaseUrl/platform-admin';

  static const String appName = 'ACA';
  static const String appFullName = 'Axon Counterbase Admin';

  /// Host shown in Account → "Connected to".
  static String get serverLabel => Uri.parse(apiBaseUrl).host;
}
