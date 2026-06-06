# MEMORY.md - Long-Term Memory

## M-Pesa AI Billing System (May 2026)

### Core Implementation

**Goal:** Build a fully automated M-Pesa-based AI subscription billing system for the Flutter POS app, integrated with backend NestJS + Prisma/PostgreSQL.

**Pricing:** 600 KES/month with 7-day free trial for new users

**M-Pesa Number:** 0742126582 (Johnne Hika)

**Key Features Implemented:**
- Auto SMS verification for M-Pesa payments (validates code format, amount=600, recipient=0742126582, timestamp freshness within 30min)
- Manual M-Pesa code entry fallback for users who can't get auto-parsed SMS
- Admin approval dashboard for revenue tracking and manual overrides
- NVIDIA NIM AI integration with BYOK (Bring Your Own Key) model - API key never exposed to users

### Technical Stack

**Mobile:** Flutter (Levisa POS) - ARM64, ARM, x86_64 APK builds
**Backend:** NestJS with Prisma ORM, PostgreSQL on localhost:5433
**Email:** Gmail (johnkimani576@gmail.com) via Himalaya CLI at ~/.config/himalaya
**Update Channel:** GitHub Releases (repo: JohnHika/Jawaki-pos)

### Database Schema

**Tables Added:**
- `pos_clients` - Stores client brands (Levisa, TSL, Kate)
- `ai_subscriptions` - Tracks subscription status (trial, active, expired)
- `ai_payments` - Stores payment records (amount, M-Pesa code, status)

**Relationships:**
- `Branch.posClientId` links each branch to its client brand
- `ai_subscriptions.branchId` links subscriptions to specific branches
- Reverse relations added in Prisma schema for querying

### Flutter Screens Fixed Issues

**Common Fixes:**
1. Removed `device_info_plus` dependency from pubspec.yaml and all Dart files
2. Fixed type mismatches: `Color?` vs `TextStyle?` in text style parameters
3. Removed `LoadingContainer` wrapper - used standard Flutter theming instead
4. Corrected DI imports: `package:levisa_adventures_pos/core/di/injection.dart`
5. Fixed `app_router.dart` parameter handling for AI screens
6. Updated `ai_status_banner.dart` with accurate trial/active/expired state logic

**APK Build & Deployment:**
- Version bump required for downgrade prevention: `1.0.0+1` → `1.0.1+2002`
- Build targets: `--target-platform android-arm64,android-arm,android-x64`
- Install command: `adb -s <device_id> install -r <apk_path>`

### Backend API Endpoints

**AI Billing (`/api/v1/ai-billing/*`):**
- `POST /trial` - Start 7-day trial
- `GET /status/:branchId` - Get subscription status
- `GET /can-use/:branchId` - Subscription check guard
- `POST /submit-payment` - Manual M-Pesa code entry
- `POST /verify-sms` - Auto verify from SMS content

**Admin (`/api/v1/admin/ai-billing/*`):**
- `GET /subscriptions` - Admin listing
- `GET /pending` - Approval queue
- `POST /handle-payment` - Approve/reject
- `GET /revenue` - Analytics
- `GET /clients` - POS client list
- `GET /clients/:slug/branches` - Per-client store list

### Security Considerations

- **NVIDIA API Key:** Never exposed to users - backend handles proxying with key held securely in `.env`
- **SMS Permissions:** Android `RECEIVE_SMS` and `READ_SMS` required for auto-parsing
- **Admin Access:** Only on user's phone (Jawaki Admin app), manages multiple client POSes

### Remaining Tasks

**In Progress:**
- End-to-end billing flow testing on device
- Android SMS permission handling UI

**Pending:**
- Generate GitHub Release `v1.0.1` to test update flow
- Test SMS parsing with sample M-Pesa messages
- Validate backend API integrations with Postman/curl
- Ensure `NVIDIA_API_KEY` present in `backend/.env`

### Key Decisions Made

1. **SMS Auto-verification** validates transaction code, amount range (590-610), recipient match, timestamp freshness (<30min), deduplication
2. **Admin Architecture** uses separate "Jawaki Admin" app on user's phone, not integrated into main POS
3. **Build Philosophy** - "Build to ship": no "for later", full end-to-end functionality, test before shipping
4. **Database** - Added `pos_clients`, `ai_subscriptions`, `ai_payments` tables with proper relationships
5. **UI Cleanup** - Removed custom color constants, `LoadingContainer`, `device_info_plus` for compatibility
6. **DI Structure** - Ensured proper injection via `package:levisa_adventures_pos/core/di/injection.dart`

## 2026-05-19 - Latest Session Notes

### Work Completed

- Fixed Flutter billing screen errors: removed `device_info_plus`, corrected type mismatches in `_CodeInputField`, `_MpesaButton`, `_InstructionStep`, `_SectionCard`
- Updated `pubspec.yaml` version: `1.0.0+1` → `1.0.1+2002` to prevent downgrade error
- Successfully built APK with `flutter build apk --release --target-platform android-arm64,android-arm,android-x64`
- Installed APK via ADB: `adb -s R5GL21132WV install -r <path>` (Streamed Install Success)
- App now ready for end-to-end testing of AI subscription flow (trial → pay → SMS verification)

### Device Context
- **Device:** Samsung SM S938B (R5GL21132WV)
- **Package:** com.levisaadventures.pos
- **APK Path:** C:\Projects\pos-system\mobile\build\app\outputs\flutter-apk\app-release.apk
