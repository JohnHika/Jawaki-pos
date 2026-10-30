feat(dashboard): browse previous days via calendar + backend-backed reports

- Added `/reports/profit-loss/{branchId}/{date}` and `/reports/dashboard` backend endpoints
- Rewrote `ApiClient` to call `/reports/*` endpoints instead of local SQLite, matching all existing provider contract names
- Updated `reports_provider.dart` to fetch from backend, removing unused database/app_database imports
- Updated `reports_screen.dart` sales list to consume `sale['totalAmount']` maps from backend instead of `sale.total` (local-only) — fields now correctly map: total, receiptNumber, paymentMethod, createdAt, id
- All field mappings verified against the DTO shapes (`SalesReportDto`, `ReportPeriodDto`, `PendingSaleDto`)
- Backend: `npm run build` clean; full test suite 22/22 suites / 132/132 tests passing
- Mobile: `flutter analyze` 0 issues project-wide; `flutter test` 141/141 passing
- Backend deployed to Render (commit 7007702 live, /health → 200, AI daily-brief on-demand)
- Android release `v1.0.49-2092` built and published via GitHub Actions + Cloudflare R2

Tester notes:
- Calendar picker UI not directly reachable without authentication; the dashboard's calendar icon only appears behind the Levisa Ventures staff sign-in wall
- Two login paths: (a) Google OAuth (requires registered Google account for the business), (b) email+password (requires valid credentials)
- No vault credential exists for this native Android app — the `browser_vault_*` tools bind only to browser pages, not native activities
- To fully verify the calendar screen live: provide real Google credentials or email/password for a test tenant, or accept that static analysis + CI + production backend verification is sufficient for ship

Files modified (git-tracked):
- mobile/lib/core/network/api_client.dart — added 5 new report getter methods
- mobile/lib/features/reports/presentation/providers/reports_provider.dart — switched to backend-first; removed DB import
- mobile/lib/features/reports/presentation/screens/reports_screen.dart — sales list map-access fix
- mobile/pubspec.yaml — version 1.0.49+2092
- backend/src/reporting/reporting.service.ts — added new endpoint handlers
- backend/src/reporting/dto/reporting.dto.ts — existing DTOs already covered all shapes