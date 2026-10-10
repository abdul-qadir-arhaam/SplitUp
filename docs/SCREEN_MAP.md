# SplitUp: SCREEN_MAP.md

> Visual screen inventory mapping Stitch MCP designs to the `APP_FLOW.md` route architecture.
> Design assets are stored in [`docs/designs/`](designs/).

---

## 1. Screen Mapping Table

| Screen ID (from APP_FLOW.md) | Stitch screen name | Saved files | Status |
|---|---|---|---|
| **S01** | SplitUp - Welcome & Sign-In | [`SplitUp - Welcome & Sign-In.png`](designs/SplitUp%20-%20Welcome%20%26%20Sign-In.png)<br>[`SplitUp - Welcome & Sign-In.html`](designs/SplitUp%20-%20Welcome%20%26%20Sign-In.html) | Screenshot & HTML saved |
| **S02 / S03** | SplitUp - Phone & OTP Verification | [`SplitUp - Phone & OTP Verification.png`](designs/SplitUp%20-%20Phone%20%26%20OTP%20Verification.png)<br>[`SplitUp - Phone & OTP Verification.html`](designs/SplitUp%20-%20Phone%20%26%20OTP%20Verification.html) | Screenshot & HTML saved |
| **S10** | SplitUp - Home & Friends Ledger | [`SplitUp - Home & Friends Ledger.png`](designs/SplitUp%20-%20Home%20%26%20Friends%20Ledger.png)<br>[`SplitUp - Home & Friends Ledger.html`](designs/SplitUp%20-%20Home%20%26%20Friends%20Ledger.html) | Screenshot & HTML saved |
| **S10 (Variant)** | SplitUp Home Dashboard | [`SplitUp Home Dashboard.png`](designs/SplitUp%20Home%20Dashboard.png)<br>[`SplitUp Home Dashboard.html`](designs/SplitUp%20Home%20Dashboard.html) | Screenshot & HTML saved |
| **S13** | SplitUp - Friend Detail: Rahul (College) | [`SplitUp - Friend Detail- Rahul (College).png`](designs/SplitUp%20-%20Friend%20Detail-%20Rahul%20(College).png)<br>[`SplitUp - Friend Detail- Rahul (College).html`](designs/SplitUp%20-%20Friend%20Detail-%20Rahul%20(College).html) | Screenshot & HTML saved |
| **S20** | SplitUp - Add Expense Modal | [`SplitUp - Add Expense Modal.png`](designs/SplitUp%20-%20Add%20Expense%20Modal.png)<br>[`SplitUp - Add Expense Modal.html`](designs/SplitUp%20-%20Add%20Expense%20Modal.html) | Screenshot & HTML saved |
| **S20 (Trip Context)** | SplitUp - Add Expense Modal (Trip Context) | [`SplitUp - Add Expense Modal (Trip Context).png`](designs/SplitUp%20-%20Add%20Expense%20Modal%20(Trip%20Context).png)<br>[`SplitUp - Add Expense Modal (Trip Context).html`](designs/SplitUp%20-%20Add%20Expense%20Modal%20(Trip%20Context).html) | Screenshot & HTML saved |
| **S30** | SplitUp - Groups | [`SplitUp - Groups.png`](designs/SplitUp%20-%20Groups.png)<br>[`SplitUp - Groups.html`](designs/SplitUp%20-%20Groups.html) | Screenshot & HTML saved |
| **S31** | SplitUp - Create Group | [`SplitUp - Create Group.png`](designs/SplitUp%20-%20Create%20Group.png)<br>[`SplitUp - Create Group.html`](designs/SplitUp%20-%20Create%20Group.html) | Screenshot & HTML saved |
| **S33 / S35** | SplitUp - Friday Gang Dashboard | [`SplitUp - Friday Gang Dashboard.png`](designs/SplitUp%20-%20Friday%20Gang%20Dashboard.png)<br>[`SplitUp - Friday Gang Dashboard.html`](designs/SplitUp%20-%20Friday%20Gang%20Dashboard.html) | Screenshot & HTML saved |
| **S36** | SplitUp - Group Settle Graph | [`SplitUp - Group Settle Graph.png`](designs/SplitUp%20-%20Group%20Settle%20Graph.png)<br>[`SplitUp - Group Settle Graph.html`](designs/SplitUp%20-%20Group%20Settle%20Graph.html) | Screenshot & HTML saved |
| **S40** | SplitUp - Trips | [`SplitUp - Trips.png`](designs/SplitUp%20-%20Trips.png)<br>[`SplitUp - Trips.html`](designs/SplitUp%20-%20Trips.html) | Screenshot & HTML saved |
| **S41** | SplitUp - Create Trip | [`SplitUp - Create Trip.png`](designs/SplitUp%20-%20Create%20Trip.png)<br>[`SplitUp - Create Trip.html`](designs/SplitUp%20-%20Create%20Trip.html) | Screenshot & HTML saved |
| **S42 / S44** | SplitUp - Goa Trip Dashboard | [`SplitUp - Goa Trip Dashboard.png`](designs/SplitUp%20-%20Goa%20Trip%20Dashboard.png)<br>[`SplitUp - Goa Trip Dashboard.html`](designs/SplitUp%20-%20Goa%20Trip%20Dashboard.html) | Screenshot & HTML saved |
| **S50** | SplitUp - Notifications | [`SplitUp - Notifications.png`](designs/SplitUp%20-%20Notifications.png)<br>[`SplitUp - Notifications.html`](designs/SplitUp%20-%20Notifications.html) | Screenshot & HTML saved |
| **S51** | SplitUp - Payment Confirmation Notification | [`SplitUp - Payment Confirmation Notification.png`](designs/SplitUp%20-%20Payment%20Confirmation%20Notification.png)<br>[`SplitUp - Payment Confirmation Notification.html`](designs/SplitUp%20-%20Payment%20Confirmation%20Notification.html) | Screenshot & HTML saved |
| **S60** | SplitUp - Profile | [`SplitUp - Profile.png`](designs/SplitUp%20-%20Profile.png)<br>[`SplitUp - Profile.html`](designs/SplitUp%20-%20Profile.html) | Screenshot & HTML saved |
| **Flow Prototype** | SplitUp Bill Splitting & Trip Ledger Flow | [`SplitUp Bill Splitting & Trip Ledger Flow.html`](designs/SplitUp%20Bill%20Splitting%20%26%20Trip%20Ledger%20Flow.html) | HTML only (no PNG in Stitch) |
| **Prototype Draft** | Untitled Prototype | *None* | Empty draft node in Stitch (no assets) |

---

## 2. Inventory Coverage Analysis

### Screens with Stitch Designs (15 core app screens / flows)
- **Onboarding:** S01 (Welcome), S02 / S03 (Phone & OTP Verification)
- **Home & Friends:** S10 (Home & Friends Ledger, Home Dashboard variant), S13 (Friend Detail - Rahul)
- **Expenses:** S20 (Add Expense Modal generic, Add Expense Modal Trip Context)
- **Groups:** S30 (Groups list), S31 (Create Group), S33/S35 (Group Dashboard), S36 (Group Settle Graph)
- **Trips:** S40 (Trips list), S41 (Create Trip), S42/S44 (Trip Dashboard)
- **Notifications & Settlements:** S50 (Notifications feed), S51 (Settlement / Payment confirmation)
- **Profile:** S60 (Profile overview)

### Screens Not Yet in Stitch (To build from `DESIGN.md` & `APP_FLOW.md`)
The following screens from `APP_FLOW.md` were not generated in Stitch and will follow the design system tokens in `DESIGN.md`:
- **S04**: Merge explainer sheet
- **S11**: Contact picker / search
- **S12**: Invite via SMS popup sheet
- **S14**: Edit friend name sheet
- **S21**: Expense detail card & activity log
- **S22**: Settle confirm sheet (sender)
- **S23**: Settlement pending state
- **S32**: Group created invite list
- **S34**: Group Expenses tab
- **S37**: Group settings screen
- **S38**: Group settle options (with offset)
- **S43**: Trip Expenses tab
- **S45**: Trip Settle tab
- **S46**: Edit trip sheet
- **S52 / S53**: Settled / Rejected states
- **S61 – S66**: Profile sub-pages (Edit Profile, Logout Dialog, Blocked Users, Notifications Prefs, Delete Account, Update Banner)
