# Business Layout Actions

Business Layout Actions lets each shop choose a trade profile and tailor the
app's day-to-day presentation. The same settings are available during workspace
setup and later in **Settings → Layout actions**.

## Current model

The feature has three layers:

1. **Trade profiles** — a primary profile controls the shop's wording and
   selling defaults. Up to three optional profiles can add relevant item
   fields, dashboard figures, shortcuts, and work areas for mixed shops.
2. **Checkout style** — grid or compact list, category filters, favourites,
   and customer lookup. Owners can also show, hide, and reorder POS actions for
   customer lookup, favourites, held sales, holding a sale, cart, price list,
   inventory, stock counts, reports, payments, and receipts. The first three
   available actions stay on the toolbar; additional actions are in its More
   menu so the counter remains usable on phone screens. Navigation actions
   continue to check the signed-in staff member's existing permissions.
3. **Workspace layout** — opening screen, visible modules, shortcut order and
   names, product details, dashboard sections, and dashboard figures.

Available starting profiles are General shop, Service counter, Bookshop,
Kamukunji sales counter, Grocery & mini market, Cafe & takeaway, Market stall &
mobile trader, Fashion & apparel, Electronics & accessories, Hardware & building
supplies, Beauty & personal care, Wholesale & distribution, Stationery & office
supplies, Motor parts & accessories, Pharmacy & health shop, Bakery & food
counter, Agrovet & farm supplies, Butchery & meat shop, Beverage & liquor shop,
and Custom layout.
Profile search also accepts common aliases and spelling variants such as
“bookstore,” “stationary,” “duka,” “chemist,” and “spare parts,” in setup,
settings, and the mixed-trade profile picker.
During setup or later in Settings, a merchant can combine a primary profile
with up to three complementary profiles. For example, a bookshop can add
stationery or a grocery can add a bakery counter. The primary profile keeps
control of terminology and selling defaults; extra profiles add relevant
product details, dashboard figures, work areas, and recommended POS actions.
Merchants can edit the combined actions before saving. When they remove a
complementary profile, its profile-only work areas, fields, shortcuts, and
dashboard recommendations are removed; choices shared with a remaining
profile keep their enabled state and order, and unrelated custom choices
remain.

POS shortcuts that open a work area stay in sync with app visibility. Adding a
screen shortcut also makes that work area visible in the app; hiding a work
area removes its POS shortcut. Staff permissions continue to control whether
the signed-in user can open it.

Owners can also create up to 12 named **quick product pages** in Layout actions,
with up to 32 existing products on each page. Examples include Textbooks,
Popular stationery, or Fast movers. Pages are stored in the shop's existing
tenant settings, so they follow the shop between devices. They filter the
existing product browser; selecting an item still goes through the normal cart,
price, stock, and payment safeguards. Removed or inactive catalog items do not
appear. A merchant can reorder, rename, edit, or remove pages without changing
catalog records.

Layout settings are presentation defaults. They do not change prices, stock,
payment routing, data, or staff permissions. Hidden modules keep their data and
permission rules. The current profile is tenant-wide and therefore applies to
all branches in that workspace.

## Dashboard controls

Owners can choose which of these sections appear on the dashboard:

- Daily figures
- End-of-day review
- Business brief
- Cost and profit
- Recent sales

They can also choose and order the revenue, transaction, average-sale, and
items-sold cards. These selections are saved with the existing tenant layout
settings and are available from onboarding and Layout actions.

## Design principles

- Start with a useful trade profile; let the owner refine it later.
- Keep the layout preview visible before saving so the owner can see what will
  change.
- Keep layout and staff permissions separate. A shortcut must never grant
  access by itself.
- Keep saved sales, product metadata, and financial records when a section is
  hidden or a profile changes.
- Offer recommendations with a reason; do not silently rearrange a live till
  based on activity.
- Avoid industry-specific flows that the product cannot actually support.
  Renaming a page is not a substitute for features such as book reservations,
  restaurant table service, or pharmacy batch controls.

## POS customization patterns and next work

Established POS products let owners arrange frequently used items and actions
into tiles and pages. Shopify documents product, variant, collection, discount,
fee, and action tiles, with reusable templates, location assignment, and phone
or tablet previews. Square documents item, variation, category, custom amount,
and shortcut tiles, plus syncing a layout across locations. These patterns are
useful when every tile keeps the signed-in staff member's existing permission,
price, stock, and payment checks.

Counterbase adapts trade profiles, catalog fields and search, terminology,
navigation, the opening screen, dashboard content, product grid/list, category
filters, favourites, toolbar actions, and named quick product pages. Product
cards can be starred from either view. Quick pages curate real catalog products
but do not create new sale types, bypass checkout rules, or grant access to
hidden work areas.

Reference patterns: [Shopify smart-grid templates](https://help.shopify.com/en/manual/sell-in-person/shopify-pos/customize-pos/smart-grid-management),
[Shopify tile editor](https://help.shopify.com/en/manual/sell-in-person/shopify-pos/customize-pos/smart-grid-management/edit),
[Square item grid](https://squareup.com/help/us/en/article/8334-set-up-item-grid).

## Next expansion

The strongest next steps are:

1. **Tile types and category pages.** Extend product pages to include category
   tiles and existing safe actions, then preview the phone and tablet view.
   Every action must route through its current permission and transaction
   validation. Keep custom-amount tiles out until discount, tax, and audit
   behavior are explicitly defined.
2. **Reusable named layouts and branch overrides.** Let an owner save a
   configured layout, reuse it at another branch, and assign a different trade
   setup to a branch when needed. Keep a workspace default for new branches.
3. **Industry actions that have real domain support.** Bookshops could add
   ISBN lookup and reorder workflows; Kamukunji wholesalers could add purchase
   intake, landed cost, and carton pricing; grocery shops could add tracked
   batch and expiry controls; fashion could add size and colour variants;
   cafes could add modifiers and kitchen tickets; pharmacies could add audited
   batch, expiry, and prescription workflows. These require product and
   transaction models, validation, and reporting before exposing them as
   profile actions. A label or metadata field alone is not enough.
4. **Setup recommendations.** After catalog import, suggest useful categories,
   searchable fields, and quick items based on the merchant's catalog. Explain
   each suggestion and require the owner to apply it.

## Trade-specific layout recipes

These are starting points for the profiles, not promises that every listed
specialized workflow already exists:

| Trade | Profile defaults that fit | Next domain workflow to build |
| --- | --- | --- |
| Bookshop | ISBN/barcode search, author/publisher/class/edition details, reader wording, stock and price-list shortcuts | ISBN catalog lookup, textbook lists, and supplier reorder suggestions |
| Kamukunji wholesaler | Case/carton/pallet tiers, import/container and partner work areas, receivables and stock focus | Purchase intake, landed-cost allocation, and supplier payment reconciliation |
| Grocery / mini market | Fast item search, category and favourite selling, units by weight/volume, stock counts | Batch and expiry tracking, wastage, and weighed-item barcode flows |
| Cafe / takeaway | Menu wording, portions, guest lookup, coupons and fast sale actions | Modifiers, order notes, kitchen tickets, and pickup status |
| Fashion | Size/colour metadata, compact SKU search, customer and price-list actions | First-class variants with stock per size/colour and exchanges |
| Electronics | Model/part search, serial/warranty metadata, partner and price-list shortcuts | Serial-number capture, warranty claims, and repair/service history |
| Pharmacy / health shop | Product code search, batch/expiry details, stock counts, supplier focus | Controlled inventory, prescription checks, batch recalls, and audit trails |
| Service counter | Service codes, session/hour/day units, client wording, payments and receipts | Appointment scheduling, staff availability, and service completion tracking |

Custom actions should be assembled from supported product capabilities and
permission-checked routes. Each profile can recommend a different home screen,
dashboard, terminology, product fields, units, and shortcut order; owners can
combine up to three related profiles and override those choices. Profile
selection remains reversible and must never silently change sale, stock, price,
payment, or staff-permission records.
