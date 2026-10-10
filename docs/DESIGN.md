# SplitUp: DESIGN.md

> Visual language and component rules for the SplitUp Android app (Flutter).
> Read with `PRD.md` (behavior) and `APP_FLOW.md` (navigation).
> **Source of truth order:** `PRD.md` decides behavior. This file decides visuals. The generated Stitch screens are the visual reference: if a Stitch screen differs from a token below, match the screen and update this file, then keep the whole app consistent with it.

---

## 1. Design Principles

1. **Money first.** Amounts are the hero of every screen. Large, monospaced, instantly scannable.
2. **Quiet and minimal.** Whitespace over decoration. Few elements per screen, one primary action.
3. **Glass with purpose.** Glass is used on a small number of surfaces, over a background that gives the blur something to refract. It is never a default card style for everything.
4. **Color carries meaning.** Green means money coming to you. Terracotta means money you owe. Brass means highlights and budget. Never use these colors decoratively.
5. **Premium, not generated.** No purple gradients, neon glow, emoji icons, stock 3D art, cartoon coins, or rows of identical cards with no hierarchy.
6. **Readable above all.** Glass must never reduce legibility. Amount panels use higher-opacity glass.
7. **Calm tone.** Friendly, light microcopy ("All squared up!") without being childish.

---

## 2. Color Tokens

### 2.1 Dark theme (default look)

| Token | Hex | Use |
|---|---|---|
| `bg.base` | `#0A1411` | App background |
| `bg.blob.emerald` | `#1FA67A` | Blurred background blob (opacity 35-45%) |
| `bg.blob.brass` | `#C9A961` | Blurred background blob (opacity 20-30%) |
| `bg.blob.teal` | `#0E5C63` | Blurred background blob (opacity 30-40%) |
| `surface.flat` | `#111C18` | Solid list rows and non-glass cards |
| `surface.flatRaised` | `#16241F` | Solid raised areas, inputs |
| `glass.fill` | `#FFFFFF` at 12-16% | Standard glass panel fill |
| `glass.fillStrong` | `#FFFFFF` at 20-25% | Glass holding amounts or key text |
| `glass.border` | `#FFFFFF` at 28-32% | 1px inner border on glass |
| `text.primary` | `#F3F1EA` | Main text |
| `text.secondary` | `#A9B4AF` | Supporting text |
| `text.muted` | `#6E7B76` | Hints, disabled, tags |
| `accent.receive` | `#1FA67A` | Money you will receive, primary buttons |
| `accent.owe` | `#E0674A` | Money you owe, destructive text, logout |
| `accent.brass` | `#C9A961` | Budget, highlights, admin tag |
| `status.warn` | `#E3A33B` | Budget 80-100%, pending attention |
| `status.info` | `#5BA7B8` | Neutral informational |
| `divider` | `#FFFFFF` at 8% | Ledger lines, separators |

### 2.2 Light theme

| Token | Hex | Use |
|---|---|---|
| `bg.base` | `#F5F2EA` | Warm paper background |
| `bg.blob.*` | Same hues at 15-25% opacity | Softer blobs |
| `surface.flat` | `#FFFFFF` | Solid rows and cards |
| `surface.flatRaised` | `#EFEBE0` | Inputs, raised areas |
| `glass.fill` | `#FFFFFF` at 55-65% | Glass panel |
| `glass.fillStrong` | `#FFFFFF` at 75-85% | Glass holding amounts |
| `glass.border` | `#FFFFFF` at 70% plus 1px `#0A1411` at 6% outer | Glass edge |
| `text.primary` | `#14201C` | Main text |
| `text.secondary` | `#4B5A54` | Supporting text |
| `text.muted` | `#86938D` | Hints |
| `accent.receive` | `#0F7F5C` | Darker green for contrast on light |
| `accent.owe` | `#C4482C` | Darker terracotta for contrast |
| `accent.brass` | `#9A7B2F` | Darker brass |
| `divider` | `#14201C` at 8% | Ledger lines |

### 2.3 Rules
- Primary buttons use `accent.receive` fill with white or near-black text, whichever passes contrast.
- Positive amounts are prefixed `+` and use `accent.receive`. Negative amounts are prefixed `-` and use `accent.owe`. Zero uses `text.secondary` with the label "Settled."
- Never place `accent.owe` and `accent.receive` text on glass without verifying 4.5:1 contrast. Use `glass.fillStrong` behind amounts.
- Chart palette (muted, in order): emerald, brass, teal, terracotta, slate `#7C8A93`, sand `#B7A98A`. Never use more than 6 series.

---

## 3. Background System

- Base color plus **2 to 3 large blurred blobs** (radius about 160 to 260 logical px, blur about 80 to 120) placed at screen edges and corners so they sit **behind glass elements**.
- Blob positions are consistent across screens with small per-screen shifts, so the app feels like one space.
- Fine grain noise overlay at 3 to 4% opacity (a tiled PNG), to avoid flat digital color.
- Implementation: build one `AppBackground` widget (`Stack` of base color, `Positioned` blurred circles using `ImageFiltered`, noise overlay). Render it **once per screen shell, not per list item**, and wrap it in a `RepaintBoundary`.

---

## 4. Typography

| Role | Font | Notes |
|---|---|---|
| UI text | **Manrope** | Weights 400, 500, 600, 700 |
| Money amounts | **IBM Plex Mono** (or any mono with tabular figures) | Enable tabular numerals so digits align in columns |

Bundle fonts as assets (no runtime network fetch).

### Type scale (logical px)

| Style | Size / line height | Weight | Use |
|---|---|---|---|
| `display.amount` | 44 / 48 | Mono 500 | Hero balance |
| `title.amount` | 32 / 36 | Mono 500 | Expense total, settle amount |
| `headline` | 22 / 28 | Manrope 700 | Screen titles |
| `title` | 17 / 24 | Manrope 600 | Section titles, list titles |
| `body` | 15 / 22 | Manrope 400 | Main body |
| `label` | 13 / 18 | Manrope 500 | Chips, tags, captions |
| `amount.row` | 16 / 22 | Mono 500 | Amounts in list rows |
| `amount.small` | 13 / 18 | Mono 400 | Graph labels, secondary amounts |

Rules:
- Use **no more than 3 text sizes on one screen**.
- The rupee symbol is rendered smaller (about 60% size) and slightly raised next to large amounts.
- Amounts use Indian grouping: `1,20,000`. Always show 2 decimals only when paise are non-zero.

---

## 5. Spacing, Radius, Elevation

- **Spacing scale:** 4, 8, 12, 16, 20, 24, 32, 40. Screen horizontal padding: 20. Section gap: 24 to 32.
- **Radius:** cards 20, sheets 28 (top corners), inputs 14, chips and buttons fully pill-shaped, avatars circular.
- **Elevation:** almost none. Only the hero glass card and bottom sheets cast a soft long shadow (`0 20 40` at 25% black in dark, 10% in light). Everything else is flat.
- **Min tap target:** 48 x 48 dp.

---

## 6. The Glass Specification

Glass recipe (dark theme baseline):

1. `BackdropFilter` with `ImageFilter.blur(sigmaX: 20, sigmaY: 20)` for panels, 28 for the bottom nav and sheets.
2. Fill: `glass.fill` (or `glass.fillStrong` for amounts).
3. 1px border using `glass.border`. Optionally a top-edge highlight: a vertical gradient border white 40% fading to 10%.
4. Soft shadow as in section 5, only on hero card and sheets.
5. Clip with `ClipRRect` matching the radius **before** the `BackdropFilter`.

### Where glass is allowed
- Hero wallet-card balance panel
- Bottom floating navigation bar
- Top bars on detail screens
- Bottom sheets (add expense, settle options)
- Search fields and selected-member strips
- Notification and confirmation cards
- Dashboard summary cards (budget gauge, charts)

### Where glass is NOT allowed
- Individual rows in long lists (friends, expenses, groups, notifications). Use `surface.flat` with a ledger divider.
- Text-heavy settings lists.
- More than **3 blurred layers on screen at once**.

### Performance fallback
Provide a `GlassCard` widget with a `reducedEffects` mode (solid tinted fill, no blur). Enable it automatically on low-end devices or if frame times are poor, and expose it as an internal flag. Every glass surface must be built from this one `GlassCard` / `GlassSheet` / `GlassBar` family, never ad hoc.

---

## 7. Money-Themed Details

Use these sparingly so the app feels like money without being kitschy:

1. **Wallet-card hero:** the home and profile balance panel is a glass card with a subtle brass hairline along the top edge and a faint ledger rule texture inside.
2. **Ledger lines:** very thin horizontal rules (`divider`) spaced about 56px apart behind list areas.
3. **Receipt edge:** expense detail cards have a zigzag or perforated bottom edge, with a dashed line before the total.
4. **Monospaced amounts everywhere,** aligned right in rows.
5. **Coin-split logo mark:** a circle divided into two offset halves. Use it on the welcome screen, empty states, and the "settled" success state.
6. **Settled state:** when a balance reaches zero show a small check inside the coin mark and the text "All squared up."

---

## 8. Iconography and Avatars

- One consistent **thin line icon set** (Phosphor or Lucide), stroke 1.5, 24px default, 20px in chips. No emoji, no filled colorful icons.
- Category icons (line style): Food, Travel, Stay, Fuel, Tickets, Shopping, Groceries, Other. Rendered in `text.secondary`, tinted when selected.
- **Avatars:** circular, 40px in lists, 56 to 96px in headers. Photo, or initials on a muted tinted disc (derive hue from the person id from a restrained palette, never bright neon). A thin 1.5px ring.
- In the settlement graph, avatars are mandatory on every node so two people with the same name stay distinguishable.

---

## 9. Components

### 9.1 Buttons
- **Primary:** solid `accent.receive`, pill, height 52, label 600. One per screen.
- **Secondary:** outlined pill with `glass.border` or `divider` color, transparent fill.
- **Text button:** label only, used for low-priority actions (Skip, Cancel).
- **Destructive:** text or outlined in `accent.owe` (Reject, Logout, Delete).
- **Settle (amount) button:** compact pill, `accent.owe`-tinted outline with the amount in mono, shown only where the user must pay.
- Disabled: 40% opacity, no shadow. Pressed: scale to 0.98 with a short fade.

### 9.2 Inputs
- Underline or soft-filled (`surface.flatRaised`), radius 14, no heavy outline boxes.
- **Amount input:** huge mono text, centered, with a custom numeric keypad. Currency symbol smaller and raised.
- Focus state: thin `accent.receive` underline.

### 9.3 Cards and list rows
- **Friend row:** avatar, name (with a small grey "Not on app" tag when relevant), right-aligned signed amount in mono, and a muted caption ("owes you" or "you owe") under it.
- **Group row:** overlapped member avatars, group name, last activity line, my balance.
- **Expense row:** category icon, title, "Paid by X" caption, my share on the right.
- **Trip card:** glass panel with an abstract muted gradient header (no stock photos), name, dates, member avatars, slim budget line.
- Separate rows with ledger lines, not boxes.

### 9.4 Bottom navigation
- Floating glass bar, 4 tabs: Home, Groups, Trips, Profile. Inset 16px from the screen edges, radius 28, blur 28.
- Active tab: filled-tint icon plus label in `text.primary`, with a small emerald pill indicator. Inactive: line icon in `text.muted`.
- Badge dot on a tab when action is needed.
- Hidden on deep screens (expense detail, add expense, create flows, graph).

### 9.5 Top bar
- Home, Groups and Trips show the screen title on the left and the **bell icon** with a red unread badge on the right.
- Detail screens use a glass top bar with back arrow, centered title, and a text action on the right.

### 9.6 Bottom sheets
- Glass, radius 28 top corners, drag handle, blurred backdrop dimming the screen behind it. Used for Add expense, Settle options, and Invite via SMS.

### 9.7 Chips and tags
- Pill, `label` text. "Not on app" in muted grey, "Admin" in brass, "Pending" in `status.warn`, "Unverified" in `status.info`.

### 9.8 Segmented control
- Used for Active/Completed, Simplified/Actual, Light/Dark/System, and split types. Glass track, selected segment solid `glass.fillStrong` with a subtle emerald underline.

### 9.9 Dialogs
- Small centered glass card, one primary and one secondary action. Used for logout confirmation and destructive actions.

---

## 10. Key Screen Patterns

### 10.1 Home
Greeting plus bell. **Wallet-card glass hero** with three figures: You are owed (emerald), You owe (terracotta), Net. Search field and Add friends pill. Friends list on a ledger-lined flat surface. Settled friends show "Settled" in muted text.

### 10.2 Friend page
Header with avatar, nickname, profile-name caption, edit-name icon. Summary glass panel with the direction line and a Settle button only when the user pays. "Also in" label chips. Expense list grouped by date. Floating **Add expense** pill.

### 10.3 Add expense sheet
Amount first with a custom keypad. Then title, category icon row, Paid by (multi-payer), Split segmented control, member list with checkboxes and the **Not there** toggle (greys out the member). A live per-person line ("Rs 300 per person"). One Save button.

### 10.4 Group and Trip dashboards
Glass summary cards. Thin-ring donut chart, paid-vs-share bars, small line sparkline. Minimal charts: thin strokes, almost no grid lines, mono labels, muted palette.

### 10.5 Trip budget meter
Semicircular glass gauge with a thin arc. Arc color by level:

| Spent | Color | Message |
|---|---|---|
| under 60% | `accent.receive` | On track |
| 60-80% | `accent.brass` | Heads up |
| 80-100% | `status.warn` | Warning, with remaining amount |
| over 100% | `accent.owe` | Over budget by Rs X |

Beside it: a precise slider plus an editable number field for the budget, and a "Rs X per day left" line when dates exist. Animate the arc smoothly (about 600 ms ease-out) when values change, and respect the system "reduce motion" setting.

### 10.6 Settlement graph
- Dark blurred backdrop, nodes as avatar circles with a ring (emerald if owed, terracotta if owing), size scaled by net amount (clamped between 40 and 72 px).
- Curved links with arrowheads, thickness scaled by amount (1.5 to 6 px), mono amount labels on the link, **dashed** for pending, solid for confirmed.
- Layout: force-directed or circular layout with collision avoidance, readable up to about 10 nodes.
- Tap a node to dim all unrelated links. Tap a link for a details sheet.
- Below the graph, a flat list of settlements. **Settle (amount)** appears only on rows where the current user pays.
- Segmented control at the top: Simplified / Actual.

### 10.7 Notifications
Rows are flat, grouped by Today / Yesterday / Earlier. Unread: small emerald dot. Actionable items show inline **Confirm** (primary) and **Reject** (outlined) buttons. Resolved items show a muted result line. Empty state uses the coin-split mark and "You're all caught up."

### 10.8 Settlement request card (receiver)
Glass card: "Aman says he paid you Rs 450", with a small line "Via UPI, today 6:42 PM", and only two buttons, Confirm and Reject.

### 10.9 Profile
Large avatar with a camera badge, name, email, read-only phone. Glass summary panel with owe and owed totals. Settings list on a flat surface. Appearance segmented control. **Log out** in `accent.owe`, separated at the bottom.

### 10.10 Create group and Create trip
Group: avatar and name at the top, admin note, selected-member chips, search, contact list split into "On SplitUp" and "From your contacts", fixed bottom Create button. Trip: name, budget (mono input), optional dates, **Add from a group** chip row, search, selected avatars, Create trip button.

### 10.11 Empty and error states
Every list screen needs one: friendly line, the coin-split mark, and one action ("Add your first friend"). Offline state: a slim banner "You're offline. Showing saved data." Errors are short and actionable, never technical.

---

## 11. Motion

- Durations: 150 to 250 ms for taps and toggles, 300 to 400 ms for sheets and screen transitions, up to 600 ms for the budget arc.
- Curves: ease-out for entrances, ease-in for exits. No bounce or overshoot.
- Page transitions: gentle fade plus 8px upward slide. Sheets rise with a slight scale on the backdrop.
- Count-up animation on the hero balance (once, on first load), subtle.
- A settled balance triggers a short check animation inside the coin mark.
- Honor system "reduce motion" by disabling non-essential animation.

---

## 12. Accessibility

- Text contrast 4.5:1 minimum (3:1 for large text). Verify amounts on glass in both themes.
- Do not rely on color alone: always pair green and terracotta with `+` or `-` and the words "owes you" or "you owe."
- Minimum tap target 48dp. Visible focus state for keyboard and switch access.
- Provide `Semantics` labels for the graph nodes and links, and always include the text list alternative.
- Support system font scaling up to 130% without breaking layouts. Amounts must not truncate (use `FittedBox` or wrap).
- Dark, light and system themes must all be fully supported.

---

## 13. Flutter Implementation Notes

1. **Theme:** build `AppTheme.dark()` and `AppTheme.light()` using Material 3 `ColorScheme` as the base, plus a custom `ThemeExtension` (`SplitUpColors`) carrying the tokens in sections 2 to 3 (receive, owe, brass, glass fills, borders, blobs).
2. **Typography:** define a `TextTheme` plus a `MoneyTextStyles` helper using the mono font with `fontFeatures: [FontFeature.tabularFigures()]`.
3. **Shared widgets** (build before any screen): `AppBackground`, `GlassCard`, `GlassSheet`, `GlassBar`, `MoneyText` (Indian formatting, sign, color by direction), `Avatar`, `PrimaryButton`, `SecondaryButton`, `SettleButton`, `AmountInput` with keypad, `FriendTile`, `ExpenseTile`, `EmptyState`, `BudgetGauge`, `SettlementGraph` (CustomPainter), `CategoryIcon`, `StatusChip`.
4. **Money formatting:** a single `formatPaise(int paise, {bool signed})` function using Indian digit grouping. Never format money inline in screens.
5. **Name rendering:** every person's name goes through the single `displayNameFor` function (see `PRD.md` 4.5).
6. **Performance:** wrap each `BackdropFilter` in a `RepaintBoundary`, limit blurred layers to 3 on screen, use `const` constructors, use `ListView.builder`, and test on a mid-range Android phone with the release build.
7. **Assets:** fonts, noise texture, logo mark and category icons are bundled locally. No network calls for visuals.
8. **No hard-coded colors, sizes or fonts in screens.** Everything comes from the theme and tokens above.

---

## 14. Do and Don't

**Do**
- Keep one primary action per screen.
- Use real-looking Indian names and rupee amounts in mock data (mix values like 1,240 and 87.50).
- Reuse the same background blobs across screens.
- Let amounts be large and aligned.

**Don't**
- Use purple or blue-purple gradients, neon glow, or emoji icons.
- Put glass on every card or on list rows.
- Add decorative coins, 3D illustrations or stock photos.
- Stack many identical rounded cards with no hierarchy.
- Use red and green alone to convey meaning.
- Hard-code colors or fonts in individual screens.
- Show a Settle button on a row where the user receives money.

---

## 15. Asset Checklist

- App icon: coin-split mark on deep green-black, with an adaptive icon foreground and background layers.
- Splash screen: coin-split mark on `bg.base`.
- Fonts: Manrope (400, 500, 600, 700), IBM Plex Mono (400, 500).
- Noise texture PNG (tileable).
- Icon set (Phosphor or Lucide) bundled as an icon font or SVGs.
- Website screenshots in light and dark mode for the download page.