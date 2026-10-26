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
   and customer lookup. Owners can also show, hide, and reorder the existing
   POS toolbar actions (customer, favourites, held sales, hold sale, and cart).
   The cart stays available so staff can always complete checkout.
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
product details, dashboard figures, and work areas.

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

Established POS products commonly let owners arrange frequently used items and
actions into tiles, group those tiles into pages, and reuse a saved layout across
locations. Shopify's POS editor supports product, variant, collection, discount,
fee, and action tiles, plus phone/tablet previews. Square's item grid supports
item, variation, category, custom-amount, and shortcut tiles. These are useful
patterns for Counterbase, provided every action continues to respect the logged
in staff member's existing permissions.

Counterbase currently adapts shop profiles, catalog fields and search,
navigation, the opening screen, dashboard content, and the POS grid/list,
category, and favourites controls. POS product cards can be starred from either
view to populate the favourites list. The next product expansion is a visual
multi-page POS editor: item/category tiles and safe action shortcuts, with a
preview before applying. Saved named layouts and branch assignment should
follow so one business can run different counters without changing every
branch's experience at once.

Reference patterns: [Shopify smart-grid templates](https://help.shopify.com/en/manual/sell-in-person/shopify-pos/customize-pos/smart-grid-management),
[Shopify tile editor](https://help.shopify.com/en/manual/sell-in-person/shopify-pos/customize-pos/smart-grid-management/edit),
[Square item grid](https://squareup.com/help/us/en/article/8334-set-up-item-grid).

## Next expansion

The strongest next steps are:

1. **A configurable POS quick grid.** The toolbar actions can now be ordered
   and tailored by trade profile. Next, support product, category, and safe
   action tiles across multiple pages. Let merchants reorder them and preview
   phone and tablet layouts before saving. Enforce existing staff permissions
   for every action.
2. **Reusable named layouts and branch overrides.** Let an owner save a
   configured layout, reuse it at another branch, and assign a different trade
   setup to a branch when needed. Keep a workspace default for new branches.
3. **Deeper trade workflows.** Expand only where the underlying domain behavior
   exists: ISBN-led book lookup and reorders; wholesale pack pricing; grocery
   batch and expiry handling; or hospitality modifiers and kitchen tickets.
4. **Setup recommendations.** After catalog import, suggest useful categories,
   searchable fields, and quick items based on the merchant's catalog. Explain
   each suggestion and require the owner to apply it.
