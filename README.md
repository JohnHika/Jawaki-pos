# Counterbase

Counterbase is Arche Axon’s downloadable point-of-sale and shop-management
application. The current product is local-first: sales, customers, products,
stock, and finance records are stored on the device, and checkout continues
without an internet connection.

## Applications

- **Mobile:** Flutter app for Android and iOS. Local business data is encrypted
  with SQLCipher; its database key and owner credentials are held in the
  platform secure store.
- **Desktop:** Flutter app for Windows, macOS, and Linux. It uses a local
  SQLCipher database and the platform credential store.

Neither app requires the retired Counterbase online POS API or its database.
Data does not sync automatically between devices. Mobile backups (`.cbmobile`)
and desktop backups (`.cbportable`) are encrypted and currently work within
their own app family. Keep separate copies of the backup password and protect
the backup file like shop data.

## What works locally

- Product catalog, customers, checkout, receipts, and stock management
- Cash and customer-credit sales, local collections, supplier records, and
  device-based finance reports
- On-device staff profiles with individual PINs and role permissions
- Encrypted backup and restore, plus migration from a prepared `.cbarchive`
- Optional AI chat and image analysis through the Axon AI Gateway only

Online payment-provider checkout, merchant payouts, cross-device staff
invitations, shared shop connections, cloud notifications, and automatic
cross-device synchronization are not part of this standalone edition.

## Axon AI Gateway

The apps connect only to `https://gateway.archeaxon.com` for the POS chat and
vision routes. AI is disabled until the owner enters an issued Gateway key in
the app’s settings. The key is stored in the operating system credential store
and is not embedded in the application. AI requests that need shop context use
limited, read-only local summaries; customer personal data and business-write
actions are not exposed to the assistant.

## Run locally

### Mobile

```powershell
cd mobile
flutter pub get
flutter run
```

### Desktop

```powershell
cd desktop
flutter pub get
flutter run -d windows
```

Desktop CI packages Windows, macOS, and Linux builds. Builds are not published
as customer releases unless the release workflow is explicitly approved and
run. Mobile release `1.0.172` remains unchanged while the standalone edition is
reviewed.

## Project layout

```text
mobile/       Flutter Android/iOS app
desktop/      Flutter Windows/macOS/Linux app
docs/         Product, migration, and release documentation
scripts/      Local archive preparation and development utilities
backend/      Retired online POS backend source; not used by standalone apps
```

See [the downloadable-app roadmap](docs/DOWNLOADABLE_APPS_ROADMAP.md) for
current limitations and release gates. Historical backend deployment notes
are not instructions for the standalone product.
