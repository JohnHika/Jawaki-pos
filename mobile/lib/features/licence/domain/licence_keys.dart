/// Arche Axon's licence public key, as 32 bytes in base64url (43 characters).
///
/// Empty on purpose. While it is empty the app enforces nothing: no trial
/// clock, no paused sales, no Plan and licence screen. It is filled in only
/// when payment collection goes live and the lawyer and accountant have signed
/// off the terms. The matching private key never enters this repository; it is
/// made with `dart run tool/licence/licence_tool.dart keygen <folder>` on
/// Arche Axon's own computer and kept off the project folder.
const String kLicencePublicKeyBase64 = '';
