# Counterbase downloadable apps

## Product boundary

- Counterbase POS runs as downloadable, local-first apps. Daily POS operations
  do not call the retired online POS API or depend on its database.
- App AI may use only the Axon AI Gateway at `gateway.archeaxon.com` after a
  per-install key is supplied and stored in the operating system credential
  store. No third-party model keys belong in an app package.
- Keep mobile release 1.0.172 unchanged. Local-first mobile changes remain
  source-only until a separately reviewed release is requested.
- The gateway hostname and Railway service are outside the POS retirement
  work and must not be changed.

## Implemented in this source pass

- Mobile standalone mode is routed to local auth and device data. Its network
  guard rejects public POS API destinations and permits the Axon gateway paths
  only when an authorized key is present.
- The first-run business profile now controls the owner's first work screen.
  Setup and later cold starts use the same path rules, so counter-first and
  catalog-first profiles are not sent to a fixed dashboard after creation.
- PIN and biometric sign-ins now re-enter through the same router decision,
  applying the saved start screen, the signed-in role's permissions, and the
  one-time staff tour instead of always opening POS.
- Successful biometric sign-in now clears the provider's locked-session flag
  before routing, so an out-of-order auth stream update cannot bounce the user
  straight back to the PIN screen.
- Auth refresh now replaces the complete user snapshot, including clearing it
  on service-side logout, instead of retaining a stale account through a
  null-coalescing `copyWith` path.
- Layout-driven home selection now uses the same capability check in local and
  connected workspaces. A saved priority can reorder work areas but cannot send
  staff to restricted Finance, reports, AI, or another inaccessible screen.
- The connected-workspace dashboard's team invitation nudge no longer refetches
  onboarding on every dashboard rebuild. It refreshes when its loader changes
  or when the user returns from team management.
- Direct links to Layout actions now require the same
  `branches.tenant.update` permission as saving layout changes, so staff who
  cannot edit the shop-wide layout are returned to Settings.
- First-run PIN confirmation now reports a mismatch on the confirmation field
  as the owner types, before they submit workspace creation.
- The Legal & Policies screen always shows standalone-edition terms, privacy,
  and AI-processing notices, including before first workspace setup. It hides
  retired subscription, auto-renewal, and merchant-settlement policies and
  handles old direct links with an edition-specific message.
- An authenticated install that still has a retired cloud session is routed to
  a local-adoption screen before opening cloud-dependent pages. The signed-in
  administrator creates a local PIN; adoption keeps the active tenant and
  branch IDs plus the encrypted database cache, then removes the old session
  tokens. The screen tells the owner that remote-only records require the
  archived data to restore. Explicitly configured private-LAN server sessions
  keep their local-network path.
- Desktop first launch creates a local business workspace and owner PIN.
- The desktop owner PIN is stored as a salted PBKDF2 verifier in OS secure
  storage. Five incorrect attempts trigger a persistent, increasing cooldown;
  older desktop PINs migrate after the next successful sign-in.
- Desktop phone-approved sign-in now sends QR start/status/claim requests to
  the configured private-LAN phone address. Public hosts, redirects, URL
  credentials, and unexpected URL paths are rejected so the pairing secret
  cannot be forwarded to an online POS service. Polling uses one in-flight
  request at a time and a shared bounded HTTP client.
- Desktop product, customer, sale, stock, dashboard, and report data use a
  per-user SQLite database. Checkout records cash locally and decrements stock
  in the same transaction.
- Desktop checkout filters by the shop's saved categories, matches both
  product names and SKUs (including barcode scanners that type into search),
  counts item quantities accurately, and does not display an unconfigured tax
  estimate as if it were calculated. The sale transaction rejects non-finite
  quantities, stock, prices, and totals before recording the receipt.
- Mobile POS quick pages now query only the products assigned to the selected
  page before loading their pricing and branch-stock metadata. Search and
  category filters are applied within that page, so a short quick page does not
  scan and map the whole shop catalog first.
- The mobile POS now streams active catalog, search, and category results in
  stable batches of 80 after each batch's price and stock are ready. The first
  products render without waiting for the full catalog, while curated quick
  pages retain their configured order. Inactive products stay available in
  Products management but are excluded in the POS database query.
- Same-product cart edits now serialize around inventory checks, preventing
  fast repeated taps from adding more units than the available stock. Product
  cards show stock-specific messages only for stock blocks; inactive products,
  invalid units, missing catalog rows, and lookup failures keep their actual
  explanation. An item removed while its quantity sheet is open cannot receive
  a false “added” confirmation.
- Local payment analytics now decode Drift's Unix-second sale timestamps with
  SQLite's `unixepoch` and device-local-time modifiers before grouping by day
  or hour. Their inclusive date windows stop one microsecond before the next
  period, preventing a midnight sale from appearing in two periods.
- The local Payments Hub now lists only methods available in device-only
  checkout. It no longer labels provider-backed online M-Pesa as an accepted
  method when that flow is disabled in the standalone edition.
- Past-day summaries now show local customer-credit sales instead of an
  unavailable M-Pesa metric, and the read-only Axon Gateway brief is exposed
  in standalone mode with a settings link when the owner key is not configured.
  AI key-storage and brief failures have separate retry actions, so the owner
  can recover the card without reloading the sales summary. Pull-to-refresh now
  stays active until the sales summary reload finishes; the AI brief reports
  loading independently.
- Payments Hub now checks status, method, receipts, analytics, customer, sale,
  and payout permissions before loading sensitive totals or showing shortcuts;
  users no longer hit routes that immediately send them back because they lack
  access. A status-permission change also reloads the hub, and in-flight
  merchant-status responses are discarded if access was revoked.
- End of Day checks the close permission before loading its sales and cash
  aggregates. Standalone Settings no longer presents a device-local shop slug
  as a copyable company code, and PIN login uses the Counterbase name.
- Axon AI's local top-products lookup uses the same end-of-day boundary, so a
  sale recorded exactly at tomorrow's midnight cannot leak into today's answer.
- The POS customer picker debounces local name searches, reuses the current
  search future when the phone field changes, ignores stale search results,
  explains loading, no-match, and local-search failure states, and disposes
  its controllers when the sheet closes. A late saved-customer lookup cannot
  overwrite a phone number the cashier has started editing. Customer creation
  from checkout skips the cloud-sync queue for local-only workspaces, prevents
  duplicate submissions, and shows a recoverable save error in the sheet.
- The general customer-creation flow also skips the cloud-sync queue in
  local-only workspaces. Device-only records stay in the encrypted local
  database instead of accumulating unsendable sync work.
- Customer creation is hidden unless the active profile has `customers.create`.
  Opening credit defaults off and requires `finance.manage_receivables`;
  scheduling or recording an installment collection checks that same
  permission both before showing the action and again when saving it.
- Owner wildcard permissions are applied consistently to grouped capabilities
  such as reports and payment navigation as well as individual actions.
- Customer statements in local workspaces are shared from the encrypted local
  sales, collection, and installment records. Only pending or overdue schedules
  are included, overdue amounts are labeled explicitly, and the statement names
  the merchant and active branch so customers can identify who sent it. Recent
  sale timestamps are converted from Drift's Unix-second storage before the
  statement formats them as dates, and only completed sales appear (a pending
  provider prompt is not treated as proof of payment).
- Standalone installs route legacy Debt Replies links to an explicit
  hosted-statement requirement instead of issuing a retired claims API request.
- AI Memory now uses tenant-scoped records in the encrypted local database,
  remains reachable in local mode, and is included in encrypted workspace
  backups. The screen states that notes are never sent to Axon Gateway or
  recalled automatically. Restoring older mobile backups leaves this new table
  empty while preserving the existing backup checks for all other tables.
- Android update installation accepts only the versioned APK asset from the
  Counterbase GitHub Releases path. Legacy manifest mirrors such as the
  failing `r2.dev` download URL are ignored; retries continue to use the
  verified release asset.
- Customer reuse matches a same-name record by its phone number or email,
  normalizing Kenyan local and `+254` phone formats. A different phone can
  create a separate customer with the same name; when contact details are
  missing or match multiple saved rows, the app asks the cashier to choose an
  existing customer or provide clearer details instead of overwriting contact
  data. Only newly created customer rows enter the cloud sync queue.
- Local checkout now validates every line's quantity, unit price, line
  discount, and net amount against the receipt subtotal, discount, tax, and
  total before writing. Credit debt must equal the full credit sale; a split
  must contain one cash tender and one credit tender whose amounts match the
  receipt total and recorded debt. The receipt, line discounts, customer
  balance, and tracked-stock deductions are saved in one SQLite transaction,
  and stock plus the customer's credit limit are rechecked inside that
  transaction.
- The desktop catalog no longer requests archived product-image URLs over the
  network; local product-photo storage remains a follow-up item.
- If Android kills the activity while the camera or gallery is open, recovered
  product photos now follow the same persistent device-save or upload path as
  a normal pick. Product recognition is available through an explicit
  “Identify with Axon AI” action; selecting or saving a photo alone never sends
  it. Vision uses the fixed Gateway with the owner key from secure storage and
  returns editable suggestions. Values are copied into the product only after
  the owner confirms them; price, cost, stock, and barcodes are never inferred.
  Standalone product forms explain when an old cloud-only image is unavailable
  and offer a local replacement instead of a broken-image preview.
- Desktop settings can copy the database to the user's Downloads folder.
- Mobile and desktop owners can select a single-shop `.cbarchive` made from
  the archived Prisma JSON export. The app decrypts and authenticates the file,
  previews the shop and record counts, then imports supported records in one
  database transaction. It can merge into the same shop or adopt an archive into
  an empty local workspace; it refuses to mix a different shop into a workspace
  that already has business data. Re-importing identical data is idempotent.
- Mobile `.cbarchive` transfers include current customer balances, collection
  receipts, and payment schedules. Restore uses explicit archived receivables
  when present and falls back to customer balance snapshots for local archives,
  avoiding both lost balances and double-counting. Original online receivable
  entries that cannot become distinct local debts remain available as labeled,
  read-only archive history.
- The mobile legacy archive path also restores supplier accounts, invoices,
  invoice lines, supplier payment history and customer-linked credit collections
  into local Finance records. It reconstructs a split receipt only when the
  archived cash and credit tenders are complete and balance exactly to the sale;
  inconsistent splits remain flagged as unreconciled. Provider payloads, remote
  receipt-image URLs and creator credentials are not imported. Preserved-only
  records can be browsed read-only in the mobile app under Settings → Local data
  → Browse imported archive history; they do not affect live inventory or
  financial totals.
- The archive preparation command filters the local JSON dump to one shop and
  excludes login secrets, provider payloads, payment account credentials, and
  statement access tokens. The `.cbarchive` uses AES-256-GCM with a
  password-derived key (PBKDF2-HMAC-SHA256, 310,000 iterations); the password
  is entered twice in an interactive terminal and never written into the file.
  Keep the password separately from the archive. The transfer file is limited
  to 45 MB of source payload.
- Prepare an archive from an interactive terminal with
  `node scripts/prepare_counterbase_archive.cjs --tenant "<exact shop id>" --output "<private path>\shop.cbarchive"`.
  The script prints shop names and record counts only after a file has been
  created; it never prints the password or decrypted customer records.
- Mobile restores into SQLCipher. Desktop imports supported operational records
  into its SQLCipher-encrypted SQLite database and retains the complete decrypted
  archive payload inside that encrypted database. Workspace settings now include
  a read-only archive browser for every original section, including suppliers,
  debt, tax details, batches, payment details, and cash close history. Browsing
  the snapshot does not alter live stock or financial totals. Desktop still
  combines stock across source branches, and imported records outside its live
  schema remain archival only. Re-selecting an identical archive adds its
  preserved payload to older imports without duplicating live records.
- Desktop has no remote POS sign-in or configurable POS API URL. Its only
  remote client is the fixed Axon AI Gateway client.
- Desktop CI packages Windows as an Inno Setup installer, macOS as a DMG and
  ZIP, and Linux as a Debian package and portable tarball. Ordinary runs upload
  artifacts; publishing a public release requires an explicit manual workflow
  input. Packages are currently unsigned.
- A fresh local Windows x64 release build for desktop version `1.1.2+4`
  completed on 2026-10-28. The latest portable package is
  `desktop/artifacts/Counterbase-Desktop-1.1.2+4-Windows-x64-local-20261028-210508.zip`
  (SHA-256 `9ECEFF0A84D8D7C17F4682A9DDE9762101636E688801D3976CB2C21D6BBE77DC`).
  It contains `Counterbase.exe`, the compiled Dart bundle, Flutter runtime, and
  SQLCipher library. Windows secure-storage keeps its prior `AxonPOS_`
  namespace so saved workspace credentials remain readable. This package is
  unsigned and unpublished. The older installer in `artifacts/` still
  references `AxonPOS.exe`; do not distribute it. Inno Setup is not installed
  on this computer, so that installer has not been rebuilt.
- After desktop Gateway vision support was added, a fresh Windows release
  build completed locally on 2026-10-29. The preview package is
  `desktop/artifacts/Counterbase-Desktop-1.1.2+4-Windows-x64-local-20261029.zip`
  (SHA-256 `C5382D116A86D256955073480A4BD8FFA963AAA6733B83ECFC3BB3557EF6CD99`).
  It is unsigned and unpublished.
- Mobile and desktop AI chat and image recognition now use only the fixed
  `gateway.archeaxon.com` `/v1/pos/chat/stream` and `/v1/pos/vision` routes.
  Both read the key from secure storage per request, fail closed when it is
  absent, and show sanitized network/auth errors. Redirects are rejected so
  bearer keys cannot be forwarded to a different host. Chat parses
  Anthropic-style SSE events and renders text as it arrives while retaining
  structured read-only tool calls. It uses a bounded agent loop with at
  most four local read-only lookups across the full question, including follow-up
  tool rounds, for local daily totals, low stock, best sellers, and product
  search. Only results needed for the user’s question are sent to the Gateway;
  customer personal data and write operations are not exposed as tools. Photos
  use on-device OCR first and go to Gateway vision only when no text is found.
  Receipt image scans use Gateway vision and remain suggestions for staff
  review. Dashboard and historical-day briefs now send only aggregate sales,
  top-product totals, and branch stock-alert counts. The AI settings disclosure
  lists these fields. The live key has not been confirmed in app settings, so
  no Gateway request has been sent during this pass.
- Mobile and desktop local-workspace owners can save or remove an Axon Gateway
  key in Settings. It is stored in the OS secure credential store. Mobile AI
  and desktop AI read this key only at request time. The desktop assistant uses
  the same fixed Gateway hostname, a bounded read-only local tool loop, and
  sanitized errors. Both screens disclose that relevant shop summaries can be
  sent to Axon Gateway when a local lookup is needed.
- Desktop AI can now analyze a user-selected JPG, PNG, or WebP image through
  the fixed `/v1/pos/vision` route. Selection, file-type checks, preview, and the
  12 MB size limit stay local; the image is sent only after the user presses
  “Analyze image.” It uses the same OS-secured per-install Gateway key as chat.
- The mobile Drift database is opened through SQLCipher with a random key in
  platform secure storage. Older plaintext SQLite files are rekeyed in place
  before Drift migrations run; failure to load the cipher stops database open
  instead of silently creating an empty shop database.
- Mobile local workspaces can save product and category photos to the app's
  private support directory. Catalog cards, product detail, checkout, receipt,
  login, and shop-brand marks render those local files without requesting any
  old cloud image URL.
- Local PDF exports and receipts read a logo from disk when it is available;
  they skip stale online logo URLs and do not wait for a cloud image request.
- Local Cash Flow shows device-recorded cash sales, debt collections, cash
  received on voided sales, cash refunds actually paid from the till, supplier
  payments, sales transaction count, and the latest local till close. A void
  prompts staff to record a refund only after cash was physically returned.
  Till close snapshots include both refund outflows and cash still held from
  voided sales. Reconciliation history reads local close events, and its action
  opens the local End of Day workflow.
- Local End of Day no longer blanks the report when an imported/legacy sale has
  an unrecognized payment label or incomplete split detail. Those amounts stay
  in total sales, appear under “Other payment methods,” and are kept out of the
  cash subtotal so the cashier can review and account for them explicitly. The
  post-close activity check now uses a branch/date index, an existence query,
  and an exclusive end-of-day boundary instead of loading all daily sales into
  memory. Local sales summaries also reject an unavailable branch instead of
  presenting it as a real zero-sales day. After a local close, changes to cash
  sales, collections, payouts, refunds, or voided-sale cash in either direction
  now mark the close for reconciliation. A local summary read failure now
  retains the End of Day screen with an actionable warning; if the figures are
  available but close-status reconciliation fails, the screen reports that
  status as unknown and disables close/re-close until it can be verified.
  When local totals are unavailable, cash movement rows say “Unavailable”
  instead of displaying misleading zero amounts. A nonzero manual cash
  movement now requires an explanation in the close note, enforced in both
  the form and the local database write.
- Local calendar day details now require an active selected branch and scope
  both totals and receipt rows to that branch, preventing other branches’ sales
  from appearing under the selected branch’s date summary.
- When debt payment needs a customer, checkout opens the customer picker in
  place. The no-results view now has one “add customer” action instead of two.
- Standalone Finance reads supplier invoices, supplier payment history, customer
  credit balances, scheduled due dates, and customer collections from the local
  encrypted database. Supplier invoice entry updates local stock in the same
  transaction. Local collections reduce the saved customer balance atomically
  and are retry-safe. Scheduled dues are checked against the live unscheduled
  balance inside the database transaction, preventing stale screens or
  overlapping saves from promising more than the customer owes. Shop-to-shop
  receivables and Paystack prompts stay hidden in standalone mode because they
  require a shared online service.
- Customer due dates can now be cancelled with an audit timestamp and actor;
  cancellation removes only the reminder, never the debt. Voiding a credit sale
  is blocked when its reversal would leave active schedules above the remaining
  customer balance, avoiding orphaned reminders that can no longer be collected.
- Receipt print, share, and PDF output call the credit portion “Credit added”
  rather than “Balance owed.” Local collections are account-level and are not
  allocated to individual sales, so receipts do not claim the original credit
  amount remains unpaid; voided or refunded receipts no longer show it as added.
- Split tender receipts normalize numeric and string amounts consistently and
  omit malformed tender breakdowns safely instead of throwing during display.
- Archive restore previews list sections kept inside the encrypted archive but
  not yet mapped to local app screens, and the confirmation action names the
  supported-record scope before the owner starts the restore. Preserved history
  records can now be opened in a full-height in-app detail sheet, so long notes
  and fields are not lost behind a truncated list preview.
- Standalone held-sale snapshots are stored in the OS-protected credential
  store. Existing local preference snapshots are copied there before their
  plaintext copies are removed. The held-sales sheet shows a restore progress
  state instead of incorrectly reporting an empty list while secure storage is
  loading. A snapshot is migrated or overwritten only
  when every held sale and line can be restored without changing its price or
  discount. If secure storage, legacy data, or unsupported coupon data cannot
  be read safely, or the secure and legacy snapshots disagree about which held
  sales exist, the app keeps both saved copies, shows a recovery warning, and
  blocks held-sale changes instead of silently replacing data with an empty
  list.
- Mobile owners can export the live SQLCipher workspace as a password-protected
  `.cbmobile` transfer file, share it through the operating system, inspect a
  selected backup before restore, and explicitly confirm replacement of local
  shop records. The receiving phone retains its own PIN and Axon Gateway key;
  held carts move with the backup. The transfer is schema-version-bound and
  intended for matching Counterbase mobile builds. Local image files are not
  included, and the mobile format is not interchangeable with the desktop
  `.cbportable` database format.
- Standalone owners can change the business logo in Settings. The image is saved
  under the app's private support directory and is never uploaded to the retired
  POS backend. The inventory batch-receive route aliases are both accessible in
  standalone mode.
- Mobile Settings labels local workspaces “Local only” even when the phone has
  internet, so network availability is not mistaken for cloud synchronization.
  First-run setup also explains that records stay on the device and need an
  encrypted backup to move to another phone.
- A local owner can reset a forgotten quick-unlock PIN after device biometric
  verification, when biometrics are enabled and enrolled. PIN verification for
  this settings action uses the same persistent retry backoff as app unlock;
  successful PIN changes and biometric unlocks clear stale lockout state.
- A fully signed-out local owner can choose biometric sign-in only when no
  active local staff profiles exist. Device biometrics identify an enrolled
  person but not which staff member passed, so shared registers disable
  biometric owner restoration and require each staff member's own PIN. Adding
  an active profile disables biometrics; removing or deactivating staff does not
  silently re-enable them. PIN entry uses the saved owner PIN length when no
  active staff remain, and expands its indicators for variable-length team PINs.
  Cloud PIN/biometric unlocks also require a non-empty session token; an empty
  token is not treated as an authenticated session.
- The mobile AI setup screen gives Gateway-key settings only to shop admins;
  staff are told to ask the owner. Gateway requests fail closed until the
  owner-issued key is present in secure storage.
- The mobile network guard parses IPv4/IPv6 literals before allowing private
  LAN access. Public hostnames that happen to start with `fc` or `fd` no longer
  pass the local-network exception.
- Mobile sync polling now runs only for an authenticated session using an
  explicitly configured private-LAN server. It stops on local-only/adoption
  states and re-evaluates when authentication or workspace mode changes, so a
  stale online session cannot keep waking cloud-sync timers.
- Standalone inventory can receive stock in multiple packaging units. Receipt
  lines and stock increments commit together in the encrypted local database;
  retries reuse the receipt id so they cannot add the same delivery twice.
  Complete batch cost details also enter the local purchase ledger; incomplete
  costs are called out so profit reports do not imply they were included. A
  local Receipts tab shows recent deliveries and their recorded supplier refs.
  Low-stock counts and warnings now use the selected branch when a local import
  contains more than one branch, and exclude products that do not track stock.
  The Inventory “Items” total excludes archived products, matching the active
  stock list. Branch transfers remain unavailable without a shared shop
  connection. If a selected local product disappears before batch receive
  opens, the app now asks the user to choose an active product instead of
  recommending a nonexistent cloud catalog refresh. An empty local inventory
  now resolves to its proper empty state instead of waiting forever for a
  catalog refresh that standalone workspaces do not run.
- Standalone Stock Counts now snapshot active inventory products and expected
  stock for the selected branch into the encrypted database. Blind counts hide
  expected quantities until hand-in; counts can be saved, resumed, reviewed,
  approved to adjust stock, or cancelled. Approval updates stock and count
  status in one database transaction, and only counted lines change. Approval
  stops if a counted product is retired or its stock changed since the
  snapshot, preventing an old count from overwriting later sales or receipts.
  Local count screens are exposed in standalone navigation; the existing API
  flow is retained for explicitly connected workspaces. The new-count sheet
  scrolls above the keyboard on short screens, respects safe areas, and locks
  the blind-count option while a count is being created.
- Local workspace setup no longer attempts a branch-hours request for the
  retired API when checking for an end-of-day reminder. It also gives a
  plain-language setup error instead of exposing raw storage exceptions.
- Local workspace creation seeds its branch and default category in a single
  database transaction. If profile or PIN persistence fails, setup rolls back
  its profile/session values, branch, remembered-login changes, and PIN verifier
  so the owner can retry.
- Standalone workspaces now support on-device cashier, stock keeper, and
  manager profiles with individual PINs, secure-storage PIN verifiers, scoped
  permissions, owner-only team management, and pause/reactivate controls.
  Accounts do not sync or invite across devices; set them up on each install.
  AI/Gateway access, device-wide security settings, and encrypted backup or
  archive operations stay owner-only.
- Local backup and archive operations verify the saved workspace-owner
  identity, not a user-editable role label. Archive file selection, preview,
  import, and history access all require that owner session.
- Archive previews are bound to the owner and active local shop that reviewed
  them, then revalidated when the restore transaction starts. Portable backup
  creation and file inspection recheck ownership after user prompts; database
  restore revalidates ownership before replacing rows and saved workspace data.
- The standalone mobile path reads dashboard, day-summary, reports, inventory,
  product catalog, customer, and payment-hub data from the device database.
  Report, inventory-forecast, catalog-category, and Finance collection errors
  distinguish local storage failures from network failures, so an offline-only
  owner is not told to troubleshoot an internet connection for a local read.
  The Inventory empty-data failure now also gives local-storage guidance in
  standalone mode.
  Cash Flow, reconciliation history, and End of Day use local records.
  Old deep links to cloud-only features now open an in-app explanation instead
  of silently sending the user back to the home screen. Those explanations now
  name the unavailable shared-service function precisely and offer the nearest
  permitted on-device workflow for staff management, inventory requests,
  provider payouts, customer accounts, and supplier records.
  The dashboard's profit adjustment writes to the on-device purchase ledger
  and is limited to staff who can record restock purchases, including at the
  route and save points. The legacy M-Pesa explainer remains reachable in local
  mode and clearly states that it cannot verify or start a payment.
  Local catalog removal archives products and categories instead of deleting
  them or reassigning products to another category. This preserves sales,
  supplier, inventory, and category-report history; owners can restore archived
  products in the catalog and archived categories in category management.
  Workspace memory is stored locally in the encrypted database and is not sent
  automatically with Axon Gateway requests. Subscription billing and merchant-
  payout setup remain outside the standalone route allowlist because they need
  server-side services.
- Standalone checkout no longer attempts cloud till-rule or coupon refreshes,
  and debt review reads the selected customer's local balance and limit. The
  sale transaction checks that limit atomically with the receipt and stock
  update, so two overlapping checkouts cannot exceed it silently. Opening an
  unknown receipt in a local workspace now reports that it is not on this
  device instead of falling through to the retired API lookup.
- Customer debt collection sheets confirm a successful local or hosted cash
  collection after closing, and release their input controllers when dismissed.
- Customer purchase history and frequently bought items now count only
  completed sales. Voiding a completed sale also reverses that customer's
  purchase count and spend total and restores the previous last-purchase date
  in the same local database transaction. Standalone checkout writes the
  purchase totals alongside the sale, so an app interruption cannot leave a
  completed receipt with stale customer aggregates.
- Creating a customer with opening credit and its first due-date schedule is
  now one local database transaction. A failed schedule write cannot leave an
  orphaned customer balance, and duplicate-name credit entry is stopped before
  changing the existing customer so additional debt is recorded from the
  customer's profile instead.
- Standalone Finance now tags till-funded supplier payments to the active
  branch and includes them as cash outflows in Cash Flow and End of Day. Till
  closes keep a separate payout amount, validate the resulting expected cash,
  and become stale when another recorded till payout is made later that day.
  Customer collection failures now explain when the on-device save failed and
  confirm that the transaction rollback left the balance unchanged; they no
  longer tell a local-only owner to check their internet connection.
- Device-only Finance records cash already received on-device and hides the
  provider M-Pesa request. Legacy M-Pesa matching and hosted statement actions
  now explain that they are unavailable without implying the retired hosted POS
  can verify them; pasted SMS never changes a debt balance.
- Standalone notification settings no longer show sales, low-stock, or backup
  switches that have no local event service behind them. The page reports that
  only on-device app notices are available in the device-only edition.
- Future Android APK builds no longer embed `api.archeaxon.com` as their API
  URL, and the scheduled workflow that kept the retired POS backend and Neon
  database warm has been removed. A debug preview APK was built locally on
  2026-10-28; no release APK was signed or published, and mobile 1.0.172 is
  unchanged.
- Android update discovery now falls back to the `latest.json` attached to the
  latest GitHub release, and new manifests advertise only the GitHub APK.
  This avoids the `r2.dev` DNS failure from blocking update checks or retries;
  the R2 mirror can still be uploaded for older clients and manual recovery.
- The Android workflow now requires a manual `publish_release` opt-in before
  signing or publishing a customer APK. Routine pushes and pull requests cannot
  release a new mobile build while the standalone edition is under review.

## Work still required before a public release

1. Expand the shared `.cbarchive` transfer beyond the common operational set.
   Mobile and desktop now create and import password-encrypted `.cbarchive`
   files for products, customers, completed sales, and stock. Cross-platform
   import previews and validates the archive, merges only into the matching
   shop or an empty workspace, and preserves the source snapshot for read-only
   history. Sale totals now carry the subtotal, tax, and line-discount fields
   required by mobile restore; older v2 files without optional line discounts
   remain readable. Balanced cash/credit split detail is retained in the
   encrypted archive and restored on mobile, but is not mapped into live
   desktop Finance. Desktop checkout still records cash only and its local
   customer model has no balance or collection ledger; archived customer
   balances and payment history are retained read-only rather than converted
   into live debt. A desktop credit/collection workflow and safe archive
   migration must be designed together before enabling credit there. Mobile
   archives now carry customer balance snapshots,
   local collection receipts, and payment schedules. Supplier finance, device
   settings, photos, held carts, and other platform-specific records remain
   outside this interchange. The full
   mobile `.cbmobile` and desktop `.cbportable` backups remain platform-specific.
2. Verify the Gateway chat and vision routes with an owner-issued key after it
   is saved in app settings. Mobile and desktop chat and vision are wired;
   chat now uses the streaming endpoint and preserves structured read-only
   tool calls across agent rounds. Live Gateway behavior still needs a
   key-backed check.
3. Audit every remaining mobile feature for server-only assumptions. Implement
   a trustworthy local equivalent or label the unavailable action clearly;
   don't show stale cached values as live. In particular, review shop-to-shop
   ledgers, invitations, and payout administration.
4. Integrate archived history further into mobile live workflows. Both apps
   now preserve the full legacy archive in encrypted local storage and expose
   archived sections read-only; these historical records do not update live
   inventory or financial totals. Reconcile imported record totals before
   shops rely on migration. Do not point the apps at the retired Neon database
   or revive its API for migration.
5. Review and sign the Windows, macOS, Linux, and mobile release artifacts,
   verify installer dependencies, update manifests, and restore guidance. The
   Windows 1.1.2+4 app compiled and was packaged as an unsigned local ZIP on
   2026-10-28; it has not been published. macOS, Linux, and mobile artifacts
   still need platform builds and review.
6. Migrate Android to built-in Kotlin only after the toolchain and every
   Android plugin are ready. This checkout currently builds with Flutter
   3.44.1, AGP 8.11.1, and Gradle 8.14; the app and 11 resolved Android
   plugins still apply the Kotlin Gradle Plugin. Keep
   `android.builtInKotlin=false` for now. Flutter's current app migration guide
   requires AGP 9, and built-in Kotlin support requires Flutter 3.47 or later;
   enabling it before migrating the plugins is likely to break Android builds.
   The current debug build succeeds with this warning, so treat this as a
   toolchain-upgrade gate rather than a current release failure.

## Mobile data protection

The SQLCipher file is stored in the app documents directory as
`pos_database_encrypted.sqlite`. The encryption key stays in platform secure
storage. Local catalog images are stored in app support storage under
`Counterbase/images`. Held carts are also stored in platform secure storage.
The mobile app can create a password-encrypted `.cbmobile` backup of the live
SQLCipher database and restore it after preview and owner confirmation. The
backup carries the shop profile, held carts, and referenced local product,
category, business-logo, and supplier-invoice receipt images (up to 128 MB
total and 16 MB per image), while the receiving phone keeps its own PIN and
Gateway key. Image paths are rebased to the receiving phone; old
format-version-1 `.cbmobile` backups remain readable. `.cbmobile` remains
schema-version-bound and is not the desktop `.cbportable` format. The
password-encrypted `.cbarchive` format is the common cross-platform transfer
for products, customers, completed sales, and stock. Mobile exports verify the
finished file by decrypting it through the same preview parser used for import.
Use `.cbmobile` when moving the full mobile workspace, including photos and
held carts, to another phone.

Archive restore retry now completes shop-identity adoption when its database
transaction committed but the app stopped before updating the local profile.
Adopting another shop reassigns device-local staff profiles to that shop's
selected branch while retaining each profile's PIN, role, and active state.
Stale tenant or branch assignments fail closed during staff sign-in, and the
restore confirmation explains the staff behavior before the owner continues.

Local staff sign-in now rebuilds permissions from the fixed device-local role
template instead of trusting the profile's serialized permission list. It also
rejects inactive or unknown-role records and prevents a staff identifier from
aliasing the owner identity. When the owner changes the device PIN, the new PIN
is checked against every staff PIN so sign-in remains unambiguous; non-owners
cannot change the owner device PIN through the service API.

## Desktop data location

The SQLCipher file is stored in the platform application-support directory
under `Counterbase/counterbase.sqlite`; its random key is held in the platform
credential store. Existing plaintext desktop databases are rekeyed in place on
first launch, and the app stops with an error if SQLCipher is unavailable or
the saved key cannot open the database. Workspace settings create a consistent
snapshot with `VACUUM INTO`, verify it with `PRAGMA quick_check`, then rekey it
to the user-selected backup password. Restore previews the shop profile and
record counts, verifies the database, rekeys it to the receiving computer's
secure key, and replaces the workspace only after explicit confirmation. The
previous database is retained as an encrypted local rollback copy.
Password-encrypted `.cbarchive` import remains available for local migration
and cross-platform transfer. Desktop can create a `.cbarchive` from its common
workspace records; the file is authenticated and decrypted again before it is
saved. Product, customer, completed-sale, and stock records are transferred.
Desktop-specific and unsupported records are not represented as live rows on
the other platform; preserve the `.cbarchive` as the read-only source snapshot.

A fresh local Windows x64 release build was completed on 2026-10-29 after the
workspace moved from `C:\Projects\POS\pos-system` to `C:\Projects\arche-axon\products\counterbase`.
The stale CMake cache was regenerated with `flutter clean`; source and prior
artifacts were preserved. The unsigned, unpublished portable package is
`desktop/artifacts/Counterbase-Desktop-1.1.2+4-Windows-x64-local-20261029-rebuilt.zip`
(SHA-256 `E2B50500432D88346FD82B73123B163ED5291137E8BE4F69811645F3F82DC0B2`).

After the Axon Gateway chat streaming and image-analysis work, another fresh
Windows x64 release build completed on 2026-10-29. The unsigned, unpublished
portable package is
`desktop/artifacts/Counterbase-Desktop-1.1.2-4-Windows-x64-local-20261029-214805.zip`
(SHA-256 `AEBC41F59162992B9DDEA57149B9EFD110BCB4F24AAE56D278D6DBF600312EB7`).
The archive contains the executable, Flutter runtime, SQLCipher library,
secure-storage plugin, and packaged app assets. It is a local preview build;
Windows installer signing and public release remain pending.

Another Windows x64 release build completed on 2026-10-29 from the current
workspace. The unsigned, unpublished preview package is
`desktop/artifacts/Counterbase-Desktop-1.1.2+4-Windows-x64-preview-20261029-221406.zip`
(SHA-256 `0CAA60B1ECD6C893BBDA801FF86618ADC85ED4EBA9C39E39D002FAF91ED4F516`).
The package contains 15 files, including the app executable, Flutter runtime,
secure-storage plugin, SQLCipher library, and compiled assets. `dart analyze
lib` reported no issues. Windows Developer Mode was already enabled; no system
setting needed to be changed.

An Android standalone preview build also completed on 2026-10-29. The
side-by-side staging APK is `mobile/artifacts/Counterbase-Android-1.0.172+2215-staging-preview-arm64.apk`
(SHA-256 `144954BB0CA676885A808A34CEBAF2CB86E16E07E0125C4C21E2DA8D191C5E75`).
It reports package `com.archeaxon.axonpos.staging`, version name
`1.0.172-staging`, and the app label `Counterbase Preview`; it is debug-signed
and does not replace production 1.0.172. This build is a local install preview,
not a customer release. No phone installation, AI Gateway request, GitHub
publish, or mobile production APK was performed.

After tightening the first-run workspace screen, a second ARM64 staging debug
preview was built on 2026-10-29:
`mobile/artifacts/Counterbase-Android-1.0.172+2215-staging-preview-arm64-onboarding-20261029.apk`
(SHA-256 `31E64804EC543A44C2A85E161E7D17CD309F30D90C484F9685D9F5646AC67EE8`).
It uses package `com.archeaxon.axonpos.staging` and version name
`1.0.172-staging`. The first setup step uses a compact local-data notice and
shows the selected shop profile in a short card. Changing it opens a searchable
picker containing the full profile list. An emulator walkthrough confirmed the
setup screen and picker are reachable at phone size. This remains a debug
preview; production 1.0.172 and its release artifact were not changed.

After correcting local customer purchase-history accounting, a new ARM64
staging debug preview was built on 2026-10-29:
`mobile/artifacts/Counterbase-Android-1.0.172+2215-staging-preview-arm64-customer-history-20261029.apk`
(SHA-256 `A41E53794ABF5760A5E6FCA2ACED7A1D019DACC63B0EFF702D9D2878F4E153C6`).
It reports package `com.archeaxon.axonpos.staging`, version name
`1.0.172-staging`, and label `Counterbase Preview`; the build succeeded and
is debug-signed. It is a separate local preview and does not replace or publish
production 1.0.172.

After hardening local staff PIN identity and permission resolution, another
ARM64 staging debug preview was built on 2026-10-29:
`mobile/artifacts/Counterbase-Android-1.0.172+2215-staging-preview-arm64-local-auth-20261029.apk`
(SHA-256 `3AB78447E11CE203C7173FC9EC16C684898837792641AB6C958C881EA26FC6D2`).
Android package inspection confirms `com.archeaxon.axonpos.staging`, version
`1.0.172-staging` (build 2215), and the `Counterbase Preview` label. It is a
debug-signed local preview only; production 1.0.172 was not changed or
published. The build reports the existing Kotlin Gradle Plugin migration
warning; keep the documented Android toolchain migration gate in place.

A local Windows x64 release build was completed on 2026-10-30 from the current
workspace. The unsigned, unpublished portable package is
`desktop/artifacts/Counterbase-Desktop-1.1.2+4-Windows-x64-local-20261030.zip`
(SHA-256 `DB7C8EB0A6698CD7CDF94D8ACAC550D0379CD0283463AFED623BCA82162540FF`).
The Windows build succeeded with the existing Developer Mode registry setting
already enabled. This is a local preview package, not a signed installer or
public release; Android production 1.0.172 remains unchanged.

After the private-LAN desktop QR sign-in fix and archive-history audit, a fresh
Windows x64 release build completed on 2026-10-30. The unsigned, unpublished
portable preview is
`desktop/artifacts/Counterbase-Desktop-1.1.2+4-Windows-x64-local-20261030-101001.zip`
(SHA-256 `C5400F747B3E1C7632D3B29CF575217EA57AB57FDA66A05E526B0D06F6D56E1F`).
The package contains 29 entries including `Counterbase.exe`, Flutter runtime,
SQLCipher, the secure-storage plugin and application assets. Targeted Dart
analysis reported no issues in the changed mobile archive and desktop workspace,
pairing and application files. No tests were run, no phone build or production
release was created, and no POS API or online payment service was contacted.
