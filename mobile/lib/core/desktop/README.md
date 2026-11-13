# Counterbase desktop layer

The phone UI and the computer UI are two layouts over the same routes and the
same data. Everything here is only used when `DesktopLayout.wantsShell(context)`
is true: a desktop platform (Windows) and a window at least 900 logical pixels
wide. Narrower windows and every Android build keep the phone layout untouched.

## What the shell gives every page

`HomeScreen` renders `DesktopShell` (lib/features/home/presentation/desktop/)
instead of the floating bottom bar. Routed pages sit on a sheet inside it:

- permanent sidebar (232px, folds to a 56px rail below 1100px and on Sell),
  grouped Workspace / Stock / Money / People / More, Settings pinned at the bottom
- top bar: sidebar toggle, Ctrl+K search, alerts bell, account menu
- status bar (24px): connection, hardware readouts, who is signed in, version
- shortcuts: Ctrl+K palette, Ctrl+B sidebar, Alt+1..9 jump to the nth sidebar item
- the page theme is `DesktopTheme.of(...)`: compact controls, flat hairline
  cards, no ripples, page-header style app bars, narrower snackbars and dialogs

Pages are the same widgets as on the phone. To make one look like a computer
page, branch on `context.inDesktopShell` (true only below the shell).

## Kit (import from `lib/core/desktop/`)

| File | Use |
|---|---|
| `desktop_layout.dart` | `DesktopLayout`, `DesktopTokens`, `DesktopPalette` (`context.desktop`), `DesktopScope`, `DesktopContent` (centred max-width body), `DesktopStatusRegistry` (publish a status-bar readout, e.g. scanner ready) |
| `desktop_widgets.dart` | `DesktopPageHeader`, `DesktopPanel`, `DesktopMetricStrip`, `DesktopSearchField`, `DesktopFilterChip`, `DesktopEmptyState` |
| `desktop_table.dart` | `DesktopDataTable<T>` (sticky header, sort, hover, arrow keys, virtualised), `DesktopColumn`, `DesktopCellText`, `DesktopStatusChip` |
| `desktop_split.dart` | `DesktopInspectorLayout` + `DesktopInspector` (row click opens a right panel, Esc closes), `DesktopListDetail` |
| `adaptive_overlays.dart` | `showAdaptiveSheet` (bottom sheet on phone, dialog or side panel on desktop), `DesktopSheetFrame` |
| `desktop_theme.dart` | the theme transform the shell applies |
| `../../features/home/presentation/desktop/desktop_command_palette.dart` | `DesktopKeyCap` and the palette |

## Rules for a desktop page

1. **No phone chrome inside the shell**: no `FloatingActionButton`, no bottom
   action bars, no pull-to-refresh, no swipe-only actions, no `showModalBottomSheet`
   (use `showAdaptiveSheet`), no big collapsing app bars, no haptics needed.
2. **Header**: use `DesktopPageHeader` (title, subtitle, primary actions at the
   right). If the page keeps a `Scaffold`, pass `appBar: null` when
   `context.inDesktopShell`. Primary action = one filled orange button.
3. **Lists of records are tables** (`DesktopDataTable`), with a toolbar
   (`DesktopSearchField` + `DesktopFilterChip`s) above and an inspector on the right
   instead of pushing a detail page. Money and counts right-aligned in tabular numerals.
4. **Width**: never let text lines or forms stretch. Wrap documents/forms in
   `DesktopContent` (max 1280, forms 760). Workspaces that fill the window
   (Sell, chat, tables) do not.
5. **Density**: 13-14px body, 36px controls, 44px table rows, 12px radii on
   panels, 8px on controls, hairline borders instead of shadows, one level of
   panel (never panels inside panels).
6. **Keyboard**: every primary action reachable without the mouse; Esc closes
   transient UI, Enter confirms; put the shortcut in the tooltip or on the button.
   Scope shortcuts to the page (`Focus` / `CallbackShortcuts`), never global,
   except the shell's own.
7. **Pointer**: hover states, `SystemMouseCursors.click` on clickable rows,
   tooltips on icon-only buttons, right-click menus where a row has actions.
8. **Fonts**: only the bundled weights exist offline (`assets/google_fonts/`):
   Sora 400/600/700/800, Plus Jakarta Sans 400/500/600/700, JetBrains Mono 700/800.
   Any other weight tries the network (and fails in tests).
9. **Colour**: warm neutrals + the single orange accent (`DesignColors.accent`).
   Text on filled orange is dark ink, never white. Orange text on light uses
   `context.desktop.accent` (deep orange) for contrast.
10. **Both themes**: check light and dark. Never hard-code a light colour.
11. **Copy**: say "computer" not "phone" on desktop ("Sign out of this computer").

## Verifying a layout without launching the app

The installed app holds the owner's live shop session, so do NOT run the app
against real data. Instead pump the desktop layout in a widget test and write a
PNG (see `test/features/home/desktop_shell_test.dart`, `test/core/desktop/desktop_kit_test.dart`
and `test/support/shot.dart`):

```dart
setUpAll(loadShotFonts);
useWindow(tester, const Size(1366, 768));      // also try 1093x566 (1366 at 125%)
... pumpWidget(...); await saveShot(tester, boundaryKey, 'build/shots/name.png');
```

Design for the 1366x768 laptop at 100% (1366x720 usable) **and at 125% scaling
(about 1093x566 logical)**: page height after chrome is only ~500px.

Build desktop layouts as presentation widgets that take plain data (so a test
can feed sample rows), and let the routed screen choose phone or desktop.
