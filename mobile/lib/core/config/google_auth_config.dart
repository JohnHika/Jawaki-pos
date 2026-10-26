import 'package:google_sign_in/google_sign_in.dart';

/// Public Google OAuth configuration for the Counterbase Android client.
///
/// This is an OAuth client identifier, not a credential. Never add a client
/// secret to this file, the APK, or source control.
const googleWebClientId =
    '160928469725-81010j35qb5jusd0arnqhk5eokm9l71f.apps.googleusercontent.com';

/// Reuse one client so returning users can be explicitly signed out of the
/// Google plugin session before the interactive account picker is launched.
final googleSignIn = GoogleSignIn(serverClientId: googleWebClientId);
