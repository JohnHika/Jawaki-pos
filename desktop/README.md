# Counterbase Desktop

Counterbase Desktop is a downloadable, local-first point-of-sale app for Windows,
macOS, and Linux. Its business workspace, catalog, customers, sales, stock, and
reports are stored in a SQLite database on the computer. Daily checkout does
not require a Counterbase cloud account or POS server.

## Design system

The desktop UI mirrors the mobile app's design system
(`mobile/lib/core/theme/design_system.dart`): near-black canvas `#0B0A0F`,
elevated surfaces `#15131C`/`#1F1C29`, signal orange `#FF7A33` as the single
interactive accent, and matching status colors. Type matches the phone: Sora
for display headings, Plus Jakarta Sans for body, and JetBrains Mono with
tabular figures for every price, count, and metric. Metric cards reuse the
mobile pattern (left accent bar, uppercase tracked label, mono value). The
theme tokens and shared widgets live in `lib/theme/counterbase_theme.dart`.

## First launch

Create a workspace with the business name, owner name, and a six-digit owner
PIN. The PIN is stored with the operating system credential store. Business
records are stored in the platform's application-support directory under
`Counterbase/counterbase.sqlite`.

This initial local workspace supports product and customer records, cash sales,
stock tracking, and local sales summaries. It does not sync with another
computer. Workspace settings can create a password-protected `.cbportable`
backup and restore it on another computer. Restore previews the shop and record
counts, then replaces the current workspace after confirmation. The prior
database is kept as an encrypted local recovery copy. The settings also import
legacy single-shop `.cbarchive` files. That migration combines stock across
source branches; keep the original archive for supplier, debt, tax, batch, and
other history this desktop edition does not display.

The owner PIN is an app lock. Counterbase stores a salted PBKDF2 PIN verifier
in the operating system credential store and applies an increasing cooldown
after repeated incorrect attempts. Counterbase encrypts the local database
with SQLCipher and keeps its random key in the operating system credential store.
Portable `.cbportable` backups use the password you choose as their encryption
key. Use at least 12 characters and store the password separately; Counterbase
cannot recover it. Restoring requires that password and explicit confirmation.
The legacy transfer archive is separately password-encrypted as well.

## Run locally

From this folder:

```bash
flutter pub get
flutter run -d windows
```

Windows builds require Visual Studio 2022 Build Tools with the MSVC x64/x86
compiler, Windows SDK, and the C++ ATL component. The Windows secure-storage
plugin includes ATL headers at compile time.

Desktop packages can be built for Windows, macOS, and Linux by
`.github/workflows/build-desktop-app.yml`. It produces a Windows `.exe`
installer, a macOS `.dmg` with an Applications shortcut, a Linux `.deb`, and a
portable Linux `.tar.gz`. Linux builds require GTK and SQLite development
libraries. The workflow uploads build artifacts; publishing a public GitHub
release requires an explicit manual workflow run with `publish_release`
enabled.

The packages are currently unsigned. Windows SmartScreen and macOS Gatekeeper
may show an installation warning until release signing credentials are set up.

## AI connection

The desktop app has no POS API connection. Workspace settings include a secure
per-install field for an Axon Gateway key, stored in the operating system
credential store. AI stays unavailable until the owner supplies the key. Chat
uses the Axon POS assistant at
`https://gateway.archeaxon.com/v1/pos/chat/stream`; image analysis uses
`https://gateway.archeaxon.com/v1/pos/vision` only after the user selects an
image and starts analysis. If a question needs shop data, the assistant can
make bounded, read-only lookups for local sales summaries, stock, best sellers,
or products. Customer personal data and business write actions are not exposed
to the assistant. Neither the Gateway key nor an AI provider key is embedded in
the app package.
