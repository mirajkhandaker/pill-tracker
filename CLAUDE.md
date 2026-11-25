# PillTrack

Offline Flutter app for medicine reminders and supply tracking (Android first; iOS deferred).
Built step by step from `pill_tracker_build_plan_v2.md`. Phases 1–7 are done, plus extras the plan
doesn't cover: prescriptions, opt-in supply tracking, prescription photos and photo scanning (OCR).

## Commands

- `flutter analyze` must report no issues, and `flutter test` must pass, before anything is called done.
- `flutter test --coverage` writes `coverage/lcov.info` (that folder is ignored by git).
- `flutter build apk --debug` works even though `flutter doctor` complains about missing cmdline-tools.
- Emulator: `Pixel_10a` (1080x2424). adb is at `~/Library/Android/sdk/platform-tools/adb`.

## Stack (differs from what the plan assumes)

- Riverpod **3.x**, flutter_local_notifications **v22** (all parameters are named), Gradle **Kotlin DSL**.
- Package id: `com.pilltrack.app.pilltrack`. `minSdk` 23; compile/target SDK are left at Flutter's defaults.
- Settings live in the SQLite `settings` table, not shared_preferences, so the background notification isolate can read them. The one exception is the onboarding flag.
- SQLite is at DB version 3. Tests use `sqflite_common_ffi` and `DatabaseHelper.forTesting(inMemoryDatabasePath)`.

## Rules and gotchas

- **Never re-save a medicine or prescription with INSERT OR REPLACE.** `DatabaseHelper.insert` defaults to REPLACE, which deletes the row first, and the cascade wipes that medicine's `dose_logs`. Update the row in place instead (see `MedicineActions.saveMedicine`).
- Every dose log goes through `DoseLogRepository.addLog`, which logs a scheduled dose at most once per day. After logging, call `NotificationService.clearDose` and then do a full sync.
- Reminder sync never calls `cancelAll` (that's only used when reminders are switched off). It keeps snoozes, whose payload ends in `|snooze`, and skips doses that are already logged.
- Keep each existing schedule's id when editing a medicine, because today's doses are matched to logs by `scheduleId`.
- Today's dose logic (`lib/data/today_doses.dart`) must not depend on Riverpod; the background isolate uses it.
- Ads: only banner and inline ads inside screens. **Never** interstitial or rewarded ads, and never lock a feature behind an ad.
- The `Medicine` constructor defaults to `trackInventory: true`, but the form defaults it to off, so pass it explicitly in tests.
- Widget tests on the long edit form need a tall test screen and `ensureVisible` before tapping.

## Remaining steps

### Bugs to fix before launch
- [ ] Adherence, streak and weekly summary only count schedules of medicines that are still active (`lib/data/adherence.dart` uses `getAllActiveWithMedicine`), so past days of stopped, finished or replaced medicines drop out.
- [ ] `DoseLog.statusMissed` is never written. History % is taken / (taken + skipped) and includes as-needed (PRN) doses, so it doesn't match the streak and weekly-summary maths and overstates adherence.
- [ ] Minor: Edit from the medicine detail screen can pass an empty schedule list if `schedulesForMedicineProvider` hasn't loaded yet, and saving would then replace the times with 08:00.

### Phase 8 — Testing
- [ ] A `NotificationService.rescheduleAll` test with a fake plugin: check how many reminders are scheduled and that PRN medicines get none.
- [ ] Home screen widget tests: the empty state, the screen with medicines, and the Mark Taken callback.
- [ ] Raise `lib/services/` coverage from 47% to at least 60%. The gaps are the notification action handler (0%), the ad service (0%) and the notification service (45%). `lib/data/` is at 80%.
- [ ] Manual checklist 8.2 on a real device or the emulator, including the reminder fixes from 2026-11-16: an early dose gets no reminder, Taken in the app and in the notification logs only once, a snooze survives opening the app, and editing a medicine keeps its history.

### Phase 9 — Pre-launch prep
- [ ] 9.1 Host the privacy policy, then replace the placeholder URL and email in `lib/features/settings/screens/settings_screen.dart`.
- [ ] 9.2 AdMob: real banner unit id in `lib/core/constants/ad_ids.dart` and real app id in `AndroidManifest.xml`. Only one banner unit is needed.
- [ ] Not in the plan: a UMP (GDPR) consent flow before ads load.
- [ ] 9.3 Release signing: `android/key.properties` plus a release `signingConfig` in `android/app/build.gradle.kts` (release builds currently use the debug key). Never commit the keystore or passwords; `android/.gitignore` already excludes them.
- [ ] 9.4 Build the release bundle with `flutter build appbundle --release`.

### Phase 10 — Play Store (manual)
- [ ] Store listing: 512px icon, 1024x500 feature graphic, screenshots, short and full descriptions.
- [ ] Play Console: privacy URL, ads declaration, content rating, 18+ target audience, data safety form. Internal testing first, then production.
- [ ] After launch: watch crashes and ANRs and AdMob numbers, reply to reviews, and ship an update within 30 days.

### Phase 11 — After launch (in priority order)
Caregiver profiles, iOS widget, translations (Spanish, Portuguese, Hindi), remove-ads purchase. A photo of the medicine itself is still open; prescription photos are done.

Tick items here as they land.
