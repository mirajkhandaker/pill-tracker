# PillTrack — Full Build Plan for Claude Code (v2)

**Target:** Flutter Android app (iOS-ready), fully offline, AdMob-monetized, medication reminder with inventory tracking for multiple medication forms (tablets, liquids, injections, inhalers, patches, etc.).

**How to use this document:** Each numbered step below is a prompt you paste into Claude Code, in order. Wait for each step to finish and verify the output before moving to the next. Steps marked `[MANUAL]` are things you do outside Claude Code.

---

## Terminology reference (used throughout the app)

### Medication forms (user-facing labels)
| Internal value | UI label |
|---|---|
| tablet | Tablet |
| capsule | Capsule |
| liquid | Liquid / Syrup |
| injection | Injection |
| inhaler | Inhaler |
| drops | Drops |
| patch | Patch |
| cream | Cream / Ointment |
| other | Other |

### Package types (user-facing labels)
| Internal value | UI label |
|---|---|
| strip | Strip |
| bottle | Bottle |
| vial | Vial |
| pen | Pen |
| canister | Canister |
| box | Box |
| tube | Tube |

### Dose units (user-facing labels)
| Internal value | Singular | Plural |
|---|---|---|
| pcs | Piece | Pieces |
| tsp | Teaspoon | Teaspoons |
| tbsp | Tablespoon | Tablespoons |
| ml | ml | ml |
| IU | IU | IU |
| mg | mg | mg |
| mcg | mcg | mcg |
| puff | Puff | Puffs |
| drop | Drop | Drops |

### Form-to-defaults mapping (used in Add Medicine screen)
| Form | Default package | Default dose unit | Notes |
|---|---|---|---|
| Tablet | Strip | Pieces | Decrement by count; strip logic applies |
| Capsule | Strip | Pieces | Same as tablet |
| Liquid / Syrup | Bottle | ml (with Teaspoon/Tablespoon options) | Decrement by ml; Teaspoon = 5 ml, Tablespoon = 15 ml |
| Injection | Vial or Pen | IU (or ml) | Decrement by IU/ml |
| Inhaler | Canister | Puffs | Decrement by puff count |
| Drops | Bottle | Drops (or ml) | Decrement by drops (approximate) |
| Patch | Box | Pieces | 1 patch per dose typical |
| Cream / Ointment | Tube | (none) | No count decrement; user manually marks refill |
| Other | Box | Pieces | Generic fallback |

---

## Phase 0 — Prerequisites (manual, do these once)

### 0.1 Install tools on your PC
- Flutter SDK (latest stable) — https://docs.flutter.dev/get-started/install
- Android Studio (for the Android SDK + emulator)
- VS Code (recommended editor with Claude Code integration)
- Git

Verify with:
```
flutter doctor
```
Fix every red X before continuing.

### 0.2 Create these accounts
- Google Play Console — one-time $25 fee, needed for publishing
- Google AdMob — free, needed for ads
- A Gmail account dedicated to this app (keeps things clean)

### 0.3 Open Claude Code in your project folder
Create an empty folder called `pilltrack` and open Claude Code inside it. All prompts below assume you're in that folder.

---

## Phase 1 — Project scaffolding

### Step 1.1 — Initialize the Flutter project

**Prompt to Claude Code:**
> Create a new Flutter project in the current directory named `pilltrack` with organization `com.pilltrack.app`. Use Android and iOS platforms only (no web, no desktop). After creation, update `pubspec.yaml` to add these dependencies with their latest stable versions: `sqflite`, `path`, `path_provider`, `flutter_local_notifications`, `timezone`, `flutter_riverpod`, `home_widget`, `google_mobile_ads`, `shared_preferences`, `intl`, `uuid`, `pdf`, `printing`, `in_app_review`. Also add `flutter_lints` under dev_dependencies. Run `flutter pub get` and confirm no errors.

### Step 1.2 — Set up project folder structure

**Prompt to Claude Code:**
> Inside `lib/`, create this folder structure and add a placeholder `.gitkeep` file in each empty folder:
> ```
> lib/
>   main.dart
>   app.dart
>   core/
>     constants/
>     theme/
>     utils/
>   data/
>     models/
>     database/
>     repositories/
>   features/
>     medicines/
>       screens/
>       widgets/
>       providers/
>     reminders/
>       screens/
>       widgets/
>       providers/
>     history/
>       screens/
>       widgets/
>     settings/
>       screens/
>     onboarding/
>       screens/
>   services/
>     notification_service.dart
>     ad_service.dart
>     widget_service.dart
> ```
> Do not add logic yet — just create the folders and empty Dart files where indicated.

### Step 1.3 — Configure Android manifest and permissions

**Prompt to Claude Code:**
> Update `android/app/src/main/AndroidManifest.xml` to include these permissions and configurations:
> - `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM` (for Android 12+ exact reminders)
> - `POST_NOTIFICATIONS` (for Android 13+)
> - `RECEIVE_BOOT_COMPLETED` (to reschedule reminders after reboot)
> - `WAKE_LOCK` and `VIBRATE`
> - Add the receiver declarations required by `flutter_local_notifications` for scheduled + action-button notifications
> - Set `android:label` to "PillTrack"
> - Set minSdkVersion to 23 in `android/app/build.gradle` (needed for exact alarms API)
> - Set targetSdkVersion and compileSdkVersion to 34
> Show me the diff of every file you change.

---

## Phase 2 — Data layer (multi-form aware)

### Step 2.1 — Terminology helpers

**Prompt to Claude Code:**
> Create `lib/core/constants/medication_types.dart` with three sets of constants:
>
> ```dart
> // Medication form (physical form of the medicine)
> const medicationForms = {
>   'tablet': 'Tablet',
>   'capsule': 'Capsule',
>   'liquid': 'Liquid / Syrup',
>   'injection': 'Injection',
>   'inhaler': 'Inhaler',
>   'drops': 'Drops',
>   'patch': 'Patch',
>   'cream': 'Cream / Ointment',
>   'other': 'Other',
> };
>
> // Package type (how the medicine is stored/sold)
> const packageTypes = {
>   'strip': 'Strip',
>   'bottle': 'Bottle',
>   'vial': 'Vial',
>   'pen': 'Pen',
>   'canister': 'Canister',
>   'box': 'Box',
>   'tube': 'Tube',
> };
>
> // Dose units — singular and plural labels
> const doseUnitsSingular = {
>   'pcs': 'Piece',
>   'tsp': 'Teaspoon',
>   'tbsp': 'Tablespoon',
>   'ml': 'ml',
>   'IU': 'IU',
>   'mg': 'mg',
>   'mcg': 'mcg',
>   'puff': 'Puff',
>   'drop': 'Drop',
> };
>
> const doseUnitsPlural = {
>   'pcs': 'Pieces',
>   'tsp': 'Teaspoons',
>   'tbsp': 'Tablespoons',
>   'ml': 'ml',
>   'IU': 'IU',
>   'mg': 'mg',
>   'mcg': 'mcg',
>   'puff': 'Puffs',
>   'drop': 'Drops',
> };
> ```
>
> Then create `lib/core/utils/dose_formatter.dart` with:
>
> - `String formatDose(double amount, String unit)` — returns "1 Teaspoon (5 ml)", "10 IU", "500 mg", "2 Puffs", "0.5 Pieces", etc. Uses singular label when amount is exactly 1, plural otherwise. For `tsp` and `tbsp`, appends ml equivalent in parentheses (1 tsp = 5 ml, 1 tbsp = 15 ml). Trims trailing `.0` for whole numbers.
> - `String formatRemaining(double amount, String unit)` — like formatDose but framed as "10 IU left", "45 ml left", "20 Pieces left". No ml conversion needed here since we always store loose units in the base unit of the form.
> - `String formLabel(String formKey)` — returns the UI label for a form key.
> - `String packageLabel(String packageKey)` — returns the UI label for a package key.
> - `String packageLabelPlural(String packageKey)` — returns the pluralized package label ("Strips", "Bottles", "Vials", etc.).
>
> Also define these mappings for defaults used in the Add Medicine screen:
>
> ```dart
> // For a given form, what package type and dose unit(s) make sense?
> const formDefaults = {
>   'tablet':    {'package': 'strip',    'units': ['pcs', 'mg']},
>   'capsule':   {'package': 'strip',    'units': ['pcs', 'mg']},
>   'liquid':    {'package': 'bottle',   'units': ['ml', 'tsp', 'tbsp']},
>   'injection': {'package': 'vial',     'units': ['IU', 'ml']},
>   'inhaler':   {'package': 'canister', 'units': ['puff']},
>   'drops':     {'package': 'bottle',   'units': ['drop', 'ml']},
>   'patch':     {'package': 'box',      'units': ['pcs']},
>   'cream':     {'package': 'tube',     'units': []},  // no decrement
>   'other':     {'package': 'box',      'units': ['pcs']},
> };
> ```
>
> Write unit tests for `formatDose` covering: whole tablet, half tablet, teaspoon (should show ml), IU, ml, milligrams.

### Step 2.2 — SQLite schema

**Prompt to Claude Code:**
> In `lib/data/database/`, create `database_helper.dart` that manages a SQLite database using `sqflite`. Implement these tables:
>
> **`medicines`**
> - `id` TEXT PRIMARY KEY (UUID)
> - `name` TEXT NOT NULL
> - `dosage_text` TEXT (free text like "500mg" — display only, not used for calculation)
> - `notes` TEXT
> - `form` TEXT NOT NULL (`tablet`, `capsule`, `liquid`, `injection`, `inhaler`, `drops`, `patch`, `cream`, `other`)
> - `package_type` TEXT NOT NULL (`strip`, `bottle`, `vial`, `pen`, `canister`, `box`, `tube`)
> - `dose_unit` TEXT NOT NULL (`pcs`, `tsp`, `tbsp`, `ml`, `IU`, `mg`, `mcg`, `puff`, `drop`)
> - `units_per_package` REAL NOT NULL (e.g. 10 tablets/strip, 100 ml/bottle, 300 IU/pen, 200 puffs/canister)
> - `packages_in_hand` INTEGER NOT NULL DEFAULT 0
> - `loose_units` REAL NOT NULL DEFAULT 0 (e.g. 2.5 ml leftover, 3 pills from an open strip)
> - `track_inventory` INTEGER NOT NULL DEFAULT 1 (0 for creams/ointments — no decrement)
> - `is_prn` INTEGER NOT NULL DEFAULT 0 (1 = as-needed, no schedule)
> - `refill_threshold_days` INTEGER NOT NULL DEFAULT 3
> - `is_active` INTEGER NOT NULL DEFAULT 1
> - `created_at` INTEGER NOT NULL (unix ms)
>
> **`schedules`** (one medicine can have multiple times per day; no rows if `is_prn = 1`)
> - `id` TEXT PRIMARY KEY
> - `medicine_id` TEXT NOT NULL (FK → medicines.id, CASCADE delete)
> - `time_of_day` TEXT NOT NULL (HH:mm 24-hour format)
> - `dose_amount` REAL NOT NULL DEFAULT 1 (in the medicine's `dose_unit`)
> - `is_variable_dose` INTEGER NOT NULL DEFAULT 0 (1 = ask user to enter actual amount at log time, e.g. insulin sliding scale)
> - `days_of_week` TEXT NOT NULL (comma-separated 1-7, "1,2,3,4,5,6,7" for daily)
>
> **`dose_logs`**
> - `id` TEXT PRIMARY KEY
> - `medicine_id` TEXT NOT NULL
> - `schedule_id` TEXT (nullable — null for PRN or manual logs)
> - `scheduled_time` INTEGER NOT NULL (unix ms; for PRN, equals action_time)
> - `action_time` INTEGER (unix ms, null while pending)
> - `dose_amount` REAL NOT NULL (actual amount taken, in dose_unit)
> - `status` TEXT NOT NULL (`taken`, `skipped`, `missed`, `pending`)
>
> **`settings`** (key-value)
> - `key` TEXT PRIMARY KEY
> - `value` TEXT
>
> Include: singleton pattern, `onCreate` with all tables + indexes on `medicine_id` columns, `onUpgrade` stub for future migrations, and helper methods `getDb()`, `insert()`, `query()`, `update()`, `delete()`, `rawQuery()`. Write a small test in `test/database_helper_test.dart` that creates the DB, inserts a tablet medicine and an insulin medicine, queries them back, and verifies the fields match.

### Step 2.3 — Data models

**Prompt to Claude Code:**
> In `lib/data/models/`, create three immutable Dart classes: `Medicine`, `Schedule`, `DoseLog`. Each should have:
> - All fields matching the SQLite columns
> - `fromMap(Map<String, dynamic>)` factory
> - `toMap()` method
> - `copyWith(...)` for immutable updates
> - `==` and `hashCode` via field equality (write manually, don't use freezed)
>
> Add these computed getters/methods on `Medicine`:
>
> - `double totalUnitsRemaining` → `(packages_in_hand * units_per_package) + loose_units`
> - `String remainingLabel` → formatted "10 IU left" / "45 ml left" / "20 Pieces left" using `dose_formatter.formatRemaining`
> - `String inventoryBreakdown` → e.g. "2 Strips + 3 loose Pieces" or "1 Bottle + 45 ml"
> - `double dailyConsumption(List<Schedule> schedules)` → sum of `dose_amount` across schedules, weighted by (days_of_week count / 7). For variable-dose schedules, use the schedule's stored dose_amount as an estimate.
> - `int daysUntilEmpty(List<Schedule> schedules)` → returns 999 if `!track_inventory` OR `is_prn` OR `dailyConsumption == 0`. Otherwise floor(totalUnitsRemaining / dailyConsumption).
> - `bool needsRefill(List<Schedule> schedules)` → `track_inventory && daysUntilEmpty(schedules) <= refill_threshold_days`
>
> Special conversion note for **liquid form**: if `dose_unit` is `tsp` or `tbsp`, the schedule stores dose_amount in that unit, but decrement math needs to be in ml. Handle this inside `Medicine`: add `double doseAmountInBaseUnit(double scheduleAmount)` that returns `scheduleAmount * 5` for tsp, `scheduleAmount * 15` for tbsp, else `scheduleAmount`. The `loose_units` field is always stored in the medicine's `dose_unit` — but for liquids, we normalize storage to ml even when the schedule uses tsp/tbsp. Document this clearly in comments.
>
> Actually — to keep things simple, **enforce this rule**: for `liquid` form, `dose_unit` is always `ml`, and schedules can be entered in tsp/tbsp but stored converted to ml. So the DB never sees tsp/tbsp for `dose_unit`; those are input-time conveniences in the UI. Update Step 2.2's dose_unit list comment to note this if needed.
>
> Write unit tests for `daysUntilEmpty` covering: daily tablet consumption, alternate-day insulin, PRN (should return 999), cream (should return 999), zero schedules.

### Step 2.4 — Repositories

**Prompt to Claude Code:**
> In `lib/data/repositories/`, create `medicine_repository.dart`, `schedule_repository.dart`, `dose_log_repository.dart`. Each takes `DatabaseHelper` in the constructor.
>
> **MedicineRepository:**
> - `getAll()`, `getActive()`, `getById(id)`
> - `insert(Medicine)`, `update(Medicine)`, `softDelete(id)`
> - `addPackages(medicineId, int count)` — increments `packages_in_hand` for refill flow
> - `decrementUnits(medicineId, double amount)` — the core inventory logic:
>   - Skip entirely if `!track_inventory`
>   - In a transaction: reduce `loose_units` by amount
>   - If `loose_units < 0` and `packages_in_hand > 0`: open a new package → `packages_in_hand--`, `loose_units += units_per_package` (which offsets the negative)
>   - Repeat opening packages if a single dose is larger than one package's worth (rare but possible)
>   - If we can't cover the dose (would leave negative even with all packages opened): still record the log with actual amount but leave `loose_units` at 0 and `packages_in_hand` at 0. Return `false` from the method so the caller can show a warning.
>   - On success return `true`.
>
> **ScheduleRepository:** `getByMedicineId(medicineId)`, `insert(Schedule)`, `update(Schedule)`, `delete(id)`, `deleteByMedicineId(medicineId)`, `getAllActiveWithMedicine()` (JOIN returning schedules with their medicine).
>
> **DoseLogRepository:**
> - `insert(DoseLog)`, `getPending()`, `getByMedicine(medicineId, sinceMs)`, `getByDateRange(startMs, endMs)`, `updateStatus(id, status, actionTime)`, `getTodayLogs()`
> - `logPrnDose(medicineId, doseAmount)` — helper for as-needed meds: inserts a taken log with scheduled_time = action_time = now, then calls `decrementUnits`.
>
> Write tests for `decrementUnits` covering:
> 1. Enough loose units (simple decrement)
> 2. Loose units go to exactly zero
> 3. Loose units go negative → open a new package
> 4. Multiple packages consumed in one call (e.g. 200 ml dose from 100 ml bottles)
> 5. Insufficient inventory (returns false)
> 6. `track_inventory = false` (returns true, no change)

---

## Phase 3 — Notification system

### Step 3.1 — Notification service

**Prompt to Claude Code:**
> In `lib/services/notification_service.dart`, build a singleton `NotificationService` wrapping `flutter_local_notifications`.
>
> Requirements:
> - `init()` — initialize plugin, request permissions (Android 13+ notification permission, iOS alerts), initialize timezone data, resolve local timezone
> - `scheduleReminder({required String id, required String medicineName, required String doseText, required DateTime time, required String payload})` — schedule an exact-alarm local notification. Title: medicine name. Body: "Time to take {doseText}" (e.g. "Time to take 10 IU", "Time to take 1 Teaspoon (5 ml)", "Time to take 2 Tablets"). Three action buttons: **Taken**, **Skip**, **Snooze 10 min**.
> - For **variable-dose** medicines (`is_variable_dose = 1`), the body is "Time to take {medicine name} — tap to enter amount". Instead of "Taken", the primary action is **Log dose** which deep-links into the app to a small dialog for entering the actual amount taken.
> - `cancelReminder(String id)`, `cancelAllForMedicine(String medicineId)`
> - `rescheduleAll(List<Schedule> schedules, List<Medicine> medicines)` — clear and re-schedule the next 7 days of notifications for all active, non-PRN schedules
> - Notification-tap callback: parse payload `medicine_id|schedule_id|scheduled_time_ms|action`, pass to a global stream
>
> Notification IDs must be deterministic hashes of `medicineId + scheduleId + dateKey` so re-scheduling doesn't create duplicates.
>
> Add a `BootReceiver` Kotlin class in `android/app/src/main/kotlin/.../BootReceiver.kt` that receives BOOT_COMPLETED and starts the Flutter engine long enough to call `rescheduleAll`. Register it in the manifest.

### Step 3.2 — Notification action handler

**Prompt to Claude Code:**
> Create `lib/services/notification_action_handler.dart`. When a notification action fires:
>
> - **Taken** (fixed dose) → insert `DoseLog(status='taken', dose_amount=schedule.dose_amount)`, call `MedicineRepository.decrementUnits(medicineId, doseAmountInBaseUnit)`. If it returns false OR the medicine now `needsRefill()`, fire a refill warning notification: "You're running low on {name} — {remainingLabel}".
> - **Log dose** (variable dose) → open the app to a small full-screen dialog with a numeric input + unit label + Save button. On save, insert log with the entered amount and call `decrementUnits`.
> - **Skip** → insert `DoseLog(status='skipped')`, no decrement.
> - **Snooze 10 min** → schedule the same notification 10 minutes later, do not log.
>
> All logic must work when the app is in the background or fully closed. Use `flutter_local_notifications`'s background handler pattern. Document in a comment how the background isolate accesses the DB (each background invocation opens its own DB connection via the singleton).

---

## Phase 4 — UI screens

### Step 4.1 — Theme and design tokens

**Prompt to Claude Code:**
> In `lib/core/theme/`, create `app_theme.dart` with Material 3 light and dark themes. Design goals:
> - **Elderly-friendly:** minimum body text 16sp, buttons min 48dp height, high contrast
> - Primary: teal (#00897B), secondary: amber (#FFB300)
> - Rounded corners 12dp, generous padding 16dp default
> - Clear focus indicators
>
> Create `lib/core/constants/app_strings.dart` with user-facing strings as static consts (prep for future localization).

### Step 4.2 — Home screen

**Prompt to Claude Code:**
> Build `lib/features/medicines/screens/home_screen.dart`. Layout:
> - AppBar: title "PillTrack", settings icon
> - Body (scrollable):
>   1. **Today's doses** — list of `DoseCard`s for each scheduled dose today (past + upcoming). Each card: medicine name, time, dose text (from `dose_formatter.formatDose`), status badge, quick "Mark Taken" button for pending. For variable-dose entries, button says "Log dose" and opens the amount-entry dialog.
>   2. **As-needed medicines** (only if any exist) — cards for PRN medicines with a big "Log a dose" button that opens the amount-entry dialog. Show `remainingLabel` below.
>   3. **My medicines** — list of `MedicineCard`s. Each shows: name, form label (e.g. "Tablet", "Injection"), `remainingLabel` when `track_inventory=true`, days until empty color-coded (red if ≤ threshold, amber if ≤ 2×threshold, green otherwise). For non-tracked medicines (creams), show only the name and form. Tap opens medicine detail.
>   4. **Banner ad** at the bottom.
> - FAB: "Add Medicine" → opens add medicine screen.
>
> Use Riverpod providers `todayDosesProvider`, `prnMedicinesProvider`, `activeMedicinesProvider`. Empty state: "No medicines yet — tap + to add your first one".

### Step 4.3 — Add/edit medicine screen (multi-form aware)

**Prompt to Claude Code:**
> Build `lib/features/medicines/screens/edit_medicine_screen.dart`. Single screen for add and edit (takes optional `Medicine?` parameter).
>
> **Step 1 — Basic info section:**
> - Name (required, text)
> - Dosage text (optional, e.g. "500 mg", "10 IU", free text, display only)
> - Notes (optional, multiline)
> - **Form** (dropdown, required) — options from `medicationForms`. Selecting a form auto-fills the sections below using `formDefaults`.
>
> **Step 2 — Inventory section** (hidden if form = `cream`; the medicine's `track_inventory` will be set to false):
> - **Package type** (dropdown, default from `formDefaults[form]['package']`, editable) — options from `packageTypes`
> - **Dose unit** (dropdown, options from `formDefaults[form]['units']`, default the first) — this is the unit the user thinks of doses in. For liquid form, if user picks Teaspoon or Tablespoon, show a small info line: "Stored as ml internally". The DB will still use `ml` as `dose_unit` for liquids; the tsp/tbsp preference is remembered per schedule below.
> - **Units per package** (number input, label changes with dose_unit: "Tablets per Strip", "ml per Bottle", "IU per Vial", "Puffs per Canister", etc.)
> - **Packages in hand** (number input, label like "Strips in hand" using `packageLabelPlural`)
> - **Loose units** (optional, number input, label like "Loose Tablets" / "ml left in open bottle" — hidden for form=patch since patches don't usually have loose count)
> - **Refill warning:** "Warn me when I have less than X days left" (slider 1–14, default 3)
>
> **Step 3 — Schedule section:**
> - Toggle at top: **"Take as needed (no schedule)"** — if ON, this becomes a PRN medicine (`is_prn=1`) and the schedule list is hidden.
> - Otherwise, a list of time slots (min 1, max 6):
>   - Time picker
>   - Dose amount input (number)
>   - Dose unit chip (defaults to medicine's dose_unit; for liquid form only, user can switch this row to Teaspoon or Tablespoon — the amount is then stored converted to ml in the schedule row)
>   - Days-of-week chips (S M T W T F S, all selected by default)
>   - Toggle: **"Variable dose (I'll enter amount each time)"** — mainly for insulin
>   - Remove button (if more than one slot)
> - "Add another time" button
>
> Bottom: Save button. On save:
> 1. Validate: name not empty; for tracked forms, units_per_package > 0; if not PRN, at least one schedule with valid time and amount
> 2. Upsert medicine + schedules in a transaction (delete existing schedules first if editing)
> 3. Call `NotificationService.rescheduleAll()`
> 4. Call `WidgetService.updateWidget()`
> 5. Pop, snackbar "Saved"
>
> On successful **add** (not edit), show an interstitial ad before popping (respect the "max 1 per session" rule in `AdService`).

### Step 4.4 — Medicine detail screen

**Prompt to Claude Code:**
> Build `lib/features/medicines/screens/medicine_detail_screen.dart`. Shows:
> - Medicine name (large), form label as subtitle (e.g. "Tablet" or "Injection")
> - Dosage text if set
> - **Inventory card** (hidden if `track_inventory=false`):
>   - Big display: `remainingLabel` (e.g. "45 ml left", "10 IU left", "20 Tablets left")
>   - Small: `inventoryBreakdown` (e.g. "2 Bottles + 45 ml")
>   - Days until empty
>   - "Add {package}s" button → dialog to add N packages to inventory
> - Schedule summary (list of times + days + dose text) — or "As-needed" badge if PRN
> - Notes if set
> - **Recent history** — last 14 days of dose_logs for this medicine. Row: date, time, dose amount + unit, status, colored dot
> - App bar actions: Edit (→ edit screen), Delete (confirmation dialog → soft delete + cancel notifications + update widget)

### Step 4.5 — History screen

**Prompt to Claude Code:**
> Build `lib/features/history/screens/history_screen.dart`. Reachable from settings.
> - Filter chips: All / Last 7 days / Last 30 days / This month
> - Grouped list by date (newest first). Row: medicine name, time, dose amount + unit (via `formatDose`), status
> - Summary card at top: "You've taken X of Y doses in this period (Z%)"
> - Button: "Export as PDF" → **shows a rewarded ad first**, then generates a PDF using the `pdf` package with a table (Date, Time, Medicine, Dose, Status) and summary. Saves to Downloads folder, opens share sheet.

### Step 4.6 — Settings screen

**Prompt to Claude Code:**
> Build `lib/features/settings/screens/settings_screen.dart`. Sections:
> - **Notifications:** master toggle, snooze duration (5/10/15 min), sound picker (default only for MVP)
> - **Data:** "Export all data as JSON", "Import data", "Delete all data" (confirmation dialog + type "DELETE" to confirm)
> - **About:** version, privacy policy link, contact email
> - **Remove ads:** button opening a "coming soon" dialog (placeholder for future IAP)

---

## Phase 5 — Home screen widget

### Step 5.1 — Widget implementation

**Prompt to Claude Code:**
> Add a home screen widget using `home_widget`. Widget shows:
> - Top row: today's date + "PillTrack"
> - Up to 3 upcoming/pending doses today: medicine name + time + short dose text (e.g. "1 Tablet", "10 IU", "5 ml") + status icon
> - If none: "All done for today"
> - Tap widget → opens app home
>
> Steps:
> 1. Kotlin widget provider at `android/app/src/main/kotlin/.../PillWidgetProvider.kt`
> 2. Widget layout `android/app/src/main/res/layout/pill_widget.xml` (RemoteViews-compatible)
> 3. Widget info at `android/app/src/main/res/xml/pill_widget_info.xml` — min 2x2, resizable
> 4. In Flutter, `lib/services/widget_service.dart` with `updateWidget()` that reads today's pending doses from the DB (using `dose_formatter` for the short dose text) and writes via `HomeWidget.saveWidgetData()` + `HomeWidget.updateWidget()`
> 5. Call `updateWidget()` after: app launch, medicine changes, dose logged
> 6. Register widget receiver in the manifest

---

## Phase 6 — AdMob integration

### Step 6.1 — AdService

**Prompt to Claude Code:**
> Create `lib/services/ad_service.dart` as a singleton wrapping `google_mobile_ads`. Provide:
> - `init()` — calls `MobileAds.instance.initialize()`
> - `getBannerAd()` — returns configured `BannerAd` with adaptive size
> - `showInterstitial(BuildContext context)` — loads and shows interstitial, enforces "max 1 per session" and "min 90 seconds since last interstitial"
> - `showRewardedAd({required VoidCallback onReward})` — loads and shows rewarded ad
>
> Use Google's test IDs during development (document that they must be swapped for production):
> - Banner: `ca-app-pub-3940256099942544/6300978111`
> - Interstitial: `ca-app-pub-3940256099942544/1033173712`
> - Rewarded: `ca-app-pub-3940256099942544/5224354917`
>
> Put both test and prod constants in `lib/core/constants/ad_ids.dart`, switched by `kReleaseMode`.

### Step 6.2 — Wire ads into screens

**Prompt to Claude Code:**
> Add banner ad at the bottom of the home screen. Wire the interstitial trigger after "add medicine" save (stubbed in Step 4.3). Wire rewarded ad on "Export as PDF" in history screen. On ad load failure, silently continue — never block UI.

---

## Phase 7 — Polish

### Step 7.1 — App icon and splash

**Prompt to Claude Code:**
> Add `flutter_launcher_icons` and `flutter_native_splash` to dev_dependencies. Create `assets/icon.png` (1024x1024, teal background with a white pill icon — generate programmatically or ask me for one). Configure both in `pubspec.yaml`, run generation commands. Splash: teal background, white "PillTrack" text.

### Step 7.2 — Empty states, error handling, loading states

**Prompt to Claude Code:**
> Review every screen. Ensure each async provider handles loading, error (with retry), and empty (illustrative empty state + CTA) cases. Wrap DB and notification calls in try/catch; log via a simple `AppLogger` in `lib/core/utils/`.

### Step 7.3 — First-run onboarding

**Prompt to Claude Code:**
> Build a 3-screen onboarding flow shown on first launch (persist "completed" in `shared_preferences`):
> 1. "Never miss a dose" — illustration + short text
> 2. "Track your inventory" — show a mock card of a medicine with "45 ml left" / "Refill in 3 days"
> 3. Permissions: notification permission + exact alarm permission with clear "why" text and a "Grant" button that triggers the OS prompt

### Step 7.4 — Retention hooks (no external analytics)

**Prompt to Claude Code:**
> Add:
> - Streak counter on home: "You've taken doses on time for N days in a row" — persist longest streak in settings table
> - Weekly summary local notification (every Sunday 8 PM): "You took X% of your doses this week"
> - After 7 days of use with ≥ 80% adherence, one-time in-app dialog for Play Store rating (`in_app_review`)

---

## Phase 8 — Testing

### Step 8.1 — Unit and widget tests

**Prompt to Claude Code:**
> Write tests for:
> - `dose_formatter.formatDose` and `formatRemaining` — cover all units, singular/plural, teaspoon/tablespoon ml conversion display
> - All repository methods, especially `decrementUnits` edge cases from Step 2.4
> - `NotificationService.rescheduleAll` — mock the plugin, verify correct schedule count and that PRN medicines are excluded
> - `Medicine.daysUntilEmpty` — all edge cases
> - Home screen: renders empty state, renders with medicines, "Mark Taken" callback fires
>
> Aim for ≥ 60% coverage on `lib/data/` and `lib/services/`. Run `flutter test --coverage` and report.

### Step 8.2 — Manual test checklist

**[MANUAL]** Test on a real Android device. Checklist:
- [ ] Add a tablet medicine → notification fires with "Time to take 1 Tablet"
- [ ] Add an insulin medicine (Injection, Vial, IU) with variable dose → notification says "tap to enter amount", dialog opens
- [ ] Add a cough syrup (Liquid, Bottle, ml, schedule in Teaspoons) → notification says "Time to take 1 Teaspoon (5 ml)"; ml decrement is correct (5 ml per dose)
- [ ] Add an inhaler (Canister, Puffs) → decrement is per-puff
- [ ] Add a PRN painkiller → no schedule; "Log a dose" button works and decrements inventory
- [ ] Add a cream (Cream, Tube) → no inventory tracking, only refill note
- [ ] Tap "Taken" from notification with app closed → count decreases, log recorded
- [ ] Reboot phone → notifications still fire at next scheduled time
- [ ] Package boundary: dose that crosses from loose_units into a new package works
- [ ] Refill warning fires when threshold reached
- [ ] Widget updates after logging a dose
- [ ] Ads load and display (test IDs)
- [ ] Dark mode looks correct
- [ ] Small (5.5") and large phone layouts both work
- [ ] Airplane mode: app fully functional except ads

---

## Phase 9 — Pre-launch prep

### Step 9.1 — Privacy policy

**[MANUAL]** Host a privacy policy on GitHub Pages or Google Sites. Key points:
- No data leaves the device
- No account, no login
- No analytics or crash reporting
- AdMob is the only third-party SDK; may collect device advertising ID per Google's policies — link to Google's ad policy
- Contact email

Save the URL — you need it for the Play Store listing.

### Step 9.2 — AdMob production setup

**[MANUAL]**
1. AdMob → create app "PillTrack" → get app ID
2. Create 3 ad units (banner, interstitial, rewarded) → copy IDs
3. Update `lib/core/constants/ad_ids.dart` production IDs
4. Add AdMob app ID to `AndroidManifest.xml`:
   ```xml
   <meta-data
       android:name="com.google.android.gms.ads.APPLICATION_ID"
       android:value="ca-app-pub-XXXXXXX~YYYYYYY"/>
   ```

### Step 9.3 — App signing

**Prompt to Claude Code:**
> Guide me through generating a release keystore. Output the exact `keytool` command, create `android/key.properties` template (do NOT put real passwords — I fill in locally and add to .gitignore). Update `android/app/build.gradle` to read from `key.properties` and configure the release signingConfig. Add `key.properties` and `*.jks` to `.gitignore`.

### Step 9.4 — Build release bundle

**[MANUAL]**
```
flutter clean
flutter pub get
flutter build appbundle --release
```
Output: `build/app/outputs/bundle/release/app-release.aab` — upload this to Play Store.

---

## Phase 10 — Play Store submission

### Step 10.1 — Store listing assets

- App icon 512x512 PNG
- Feature graphic 1024x500 PNG
- At least 2 screenshots per device size, 1080x1920 recommended
- Short description (80 chars): "Track medications and inventory — never miss a dose or run out."
- Full description (up to 4000 chars): highlight multi-form support (tablets, insulin, syrups, inhalers, patches), inventory tracking, elderly-friendly, fully offline, no account

### Step 10.2 — Play Console setup

1. Create app, fill name, language, free/paid
2. Complete "App content":
   - Privacy policy URL
   - Ads: **Yes, contains ads**
   - Content rating: complete questionnaire (Everyone)
   - Target audience: 18+ (medication app — safer)
   - Data safety: declare AdMob collects advertising ID; everything else stays on device
3. Upload AAB to **Internal testing** track first (review ~1 day)
4. Add yourself as internal tester, install via opt-in link, run manual checklist
5. Promote to **Production**. First production review takes 3–7 days.

### Step 10.3 — Post-launch

**[MANUAL]**
- Monitor Play Console → Crashes & ANRs daily for first two weeks
- Monitor AdMob dashboard for eCPM and fill rate
- Reply to every review, especially negative
- Ship a small update within 30 days — Play Store favors active maintenance

---

## Phase 11 — Iteration priorities (post-launch)

In order of impact:
1. **Multiple profiles** (for caregivers) — unlocks parents/kids tracking
2. **Photo of medicine/strip** — helps identification
3. **Widget for iOS** — expand after Android proves out
4. **Localization** — Spanish, Portuguese, Hindi first
5. **Remove-ads IAP** at $2.99 — only after ≥ 5k DAU

---

## Summary checklist for Claude Code sessions

When you sit down to work, paste **one step at a time**. After each step:
1. Read the diff
2. Run `flutter analyze` — no warnings
3. Run `flutter test` — all pass
4. Run on emulator to sanity-check the UI
5. Commit to git: "Step 4.2: home screen"

If a step is too big and Claude Code struggles, split it into "part A / part B" — for example, do the schema (2.2) first, then models (2.3), then repositories (2.4), testing each in isolation.

Good luck.
