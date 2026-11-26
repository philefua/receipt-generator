# Audit Findings (Handoff Phase 1)

- Date: 22 Nov 2026
- Code baseline: `main` at `a379635`, plus the unmerged branch `daily-expenses` (`2c0898f`)
- Handoff used: `HANDOFF_FINANCIAL_REPORTS_1.md` (the updated version)
- This phase changes no code. It records what the app does today so later phases can be additive and safe.

---

## 1. Headlines

1. Everything the handoff asks for can be built additively. Nothing found blocks it.
2. All data lives in Hive boxes with **generated** adapters (`hive_generator`, `build_runner`). Regenerating them with the project's current packages changed nothing on the existing models, so they are in sync with the code. New fields can be added at higher indexes with defaults.
3. Money is stored as `double` and rounded to 2 decimal places. New code matches this (Section 3).
4. Receipt codes are 5 characters with a 2-digit daily serial (max 99 a day), looked up by exact match. A `-B` suffix with its own daily counter is safe (Section 4).
5. The Excel package (4.0.6) can write real formulas, custom number formats and column widths. It has **no freeze-pane support**, so frozen header rows are skipped as the handoff allows (Section 5).
6. The existing Google Drive backup is only the receipt-history Excel file. It has no settings, no presets, and **no restore function exists**. Section 6C of the handoff (backup, restore, device migration) is entirely new work (Section 7).
7. Licensing is untouched by the display-name change. Only three label lines change (Section 8).
8. **One contradiction in the handoff needs a decision before phase 4** (Conflict C1 in Section 10).
9. GitHub Actions only builds an APK on a push to `main`. Per-phase CI builds from the working branch need a trigger decision (C2).

---

## 2. Hive: boxes, typeIds, adapter style

| Box | Model | typeId | Fields in use | Notes |
|---|---|---|---|---|
| `settings_box` | `BusinessSettings` | 0 | 0 to 15 | Includes the manager password **hash** (SHA-256), receipt counter fields, `lastBackupAt`, `lastSyncAt`, `googleSheetId` |
| `products_box` | `ProductPreset` | 1 | n/a | Soft-delete (active flag), never hard-deleted |
| `receipts_box` | `Receipt` | 2 | 0 to 14 | Immutable. Only ever written with `add()` |
| (nested) | `ReceiptItem` | 3 | 0 to 4 | Frozen price snapshots |
| `license_state` | `LicenseState` | 4 | n/a | **Do not touch.** Excluded from backups |
| `expenses_box` | `Expense` | 5 | 0 to 15 | Exists only on the unmerged branch and the test tablet. To be replaced |

- Free typeIds: **6 and above**. typeId 5 is free again once the branch is reworked, because the current expense model never shipped.
- `Hive.initFlutter()` default storage path, no encryption.
- Adding a field to an existing model: use `@HiveField(n, defaultValue: ...)` with a new, higher index, then run `build_runner`. Old records have fewer stored fields, so the new field reads its default. This must be proven in phase 5 by reading a record written by the old adapter.
- Box naming convention in the project is `<name>_box`. Proposal: new boxes follow it (`finance_settings_box`, `assets_box`, `loans_box`, `loan_transactions_box`, `receipt_links_box`, `stock_counts_box`, plus the expense and category boxes). Record the final names and typeIds in `CLAUDE.md` in the last phase.
- New boxes must open inside try/catch so a failure cannot stop the app launching (handoff 2.1).

---

## 3. Money

- Every amount in receipts, deposits, balances and totals is a `double`, rounded with `double.parse(x.toStringAsFixed(2))`. There are no integer minor units.
- New models use `double` as well (handoff 4.1: match the existing approach).
- Recommendation for the pure-Dart report engine: convert amounts to integer minor units (x100, rounded) while summing, and convert back for output. Storage stays `double`. This keeps sheet totals reconciling exactly and avoids floating-point drift.

---

## 4. Receipts and numbering

- `Receipt` fields (0 to 14): code, issue time, items, subtotal, discount percent, discount amount, total payable, cashier name, locked flag, customer name, customer WhatsApp, payment method, coupon reference, deposit paid, balance owed.
- Saving: `finalizeAndSaveReceipt()` builds a frozen `Receipt` and calls `_receiptsBox.add(...)`. There is no edit or delete path anywhere.
- Code format: year letter + month letter + day letter + 2-digit serial, for example `ZKq05`.
  - Year letter counts backwards from `Z` (2026); supported years are 2026 to 2051.
  - Month is `A` to `L`. Day is `a` to `z`, then `A` to `E` for days 27 to 31.
  - The daily serial runs 01 to 99. The counter and its date live in `BusinessSettings` (`dailyReceiptCounter`, `lastReceiptCounterDate`).
  - The code is only ever used as text (print, WhatsApp share, history) and looked up by `findReceiptByCode(code)`, an exact match. No parsing regex exists.
- Balance receipts (handoff 5.3): a `-B` suffix is safe for lookup. They need **their own daily counter** so they do not use up the 99 sale slots. Proposal: store that counter in the new finance settings box, not in `BusinessSettings`, to avoid editing that adapter.
- Payment methods in the app today: **Cash, Transfer, POS** (a dropdown on the cashier screen).
- There is no cashier login. `cashierName` is a constant ("Front Desk"). So `createdByRole` (cashier or manager) must be derived from **where the entry was made** (cashier screen or Manager Backend).
- Legacy balance payments in existing data are ordinary sale receipts whose only item is named after the original receipt code (for example an item "ZKq05 x1"). Handoff 5.5 covers them.

---

## 5. Excel package

- Package: `excel` 4.0.6 (locked).
- Supported and verified in the package source:
  - real formulas (`FormulaCellValue`)
  - custom number formats (`CustomNumericNumFormat`)
  - column widths
  - real date cells (date cells get a date number format automatically when appended)
- Not supported: freeze panes (none found in the package). Skip them, as handoff 6.5 allows. No package upgrade.
- Caution: formulas written by this package carry **no cached results**. Excel and Google Sheets calculate them on open, but some phone previewers show blanks or zeros until opened properly. Note this in the Notes sheet. If previews matter, fall back to computed values (handoff 6.5 allows it).
- The receipt-history workbook (15 columns) is built in two places: `lib/main.dart` (daily auto-backup) and `lib/pages/backend_page.dart` (manual export and Backup Now). Both stay unchanged.
- Report generation can run in an isolate with `compute`. The engine is pure Dart, and the `excel` package is pure Dart too. Hive and plugins cannot be used inside the isolate, so data is read first and passed in.

---

## 6. Routing and access control

- No named routes and no drawer. `RootShell` shows a bottom `NavigationBar` (**Cashier**, **Manager**) over an `IndexedStack` of the two pages.
- App-bar actions (printer setup, receipt history, and on this branch the expenses icon) belong to `RootShell`, so they appear on **both** tabs.
- Manager gate: the Manager tab shows a lock screen. The entered password is hashed and compared with `managerPasswordHash`. The default on first install is `admin123`.
- The unlocked flag is a field of the Manager page's state. Because `IndexedStack` keeps it alive, the Manager stays unlocked until the **Lock** button is tapped or the app restarts. There is no automatic lock when switching to the Cashier tab. This is existing behaviour. It is flagged for the owner but is out of scope for this work.
- Reports, Assets, Loans, Finance Settings and expense management go **inside** the Manager page, behind that gate. That keeps them unreachable from the cashier screens (handoff 7).
- The only cashier-facing addition allowed is the single "Log Expense" entry point (handoff 4.3).

---

## 7. Backup and restore (handoff 6C audit)

- **What is backed up today:** the receipt-history Excel file only (15 columns), uploaded to the manager's Google Drive as a **new** file each time (`receipt_history_backup_<timestamp>.xlsx`, `drive.file` scope). On the unmerged branch an expense ledger file is uploaded after it.
- **Not included:** business settings, product presets, counters, password hash, licence.
- **Triggers:** manual "Backup Now" in Manager > Google Sync, and automatic on app launch when 24 hours have passed since `lastBackupAt`. Automatic failures are silent by design.
- **Restore:** none exists. The Excel format cannot be restored faithfully (dates are text, items are one string).
- **Local backup file:** none. The Excel export goes through the share sheet only.
- **Secrets:** Google tokens are managed by `google_sign_in`, not stored in Hive. The manager password is stored only as a hash, so it can go into a backup. The licence is in its own `license_state` box, so excluding it is simple.
- **Design implications for phase 11:**
  - a central list of boxes to back up, so a box cannot be forgotten
  - a versioned envelope (`schemaVersion`, app version, per-box counts and checksum)
  - restore into temporary boxes, validate, then swap
  - the existing boxes are opened at startup, so the swap needs a controlled re-initialisation
  - `lastBackupAt` today means "the receipt-history Excel upload succeeded". The new "Last backup" on the dashboard must mean a full data backup, so it needs its own value.

---

## 8. Licensing and display name (Feature A)

Where the old name appears:

| Where | Today | Action |
|---|---|---|
| `android/app/src/main/AndroidManifest.xml` line 14 | `android:label="receipt_generator"` | Change to `Printiverse` |
| `ios/Runner/Info.plist` `CFBundleDisplayName` | `Receipt Generator` | Change to `Printiverse` (iOS is not built, harmless) |
| `lib/main.dart` line 54 | `MaterialApp(title: 'Receipt Generator')` | Change to `Printiverse` |

Must not change: the Android `applicationId`/namespace (`com.example.receipt_generator`), the `device_id` method channel name, `name:` in `pubspec.yaml`, `CFBundleName`, the signing keystore.

Two optional visible strings, left alone unless the owner approves:
- `lib/pages/license_lockout_page.dart`: the pre-filled WhatsApp licence request says "...activation code for Receipt Generator". This is licensing UI, so handoff rule 3 says leave it.
- `lib/services/google_drive_service.dart`: the Drive product-sheet template is created with the name "Receipt Generator - Product List". It is only a creation name (it is never searched by name), so it is safe either way.

Licence binding and verification:
- The device ID is Android's `ANDROID_ID`. On Android 8 and later this value depends on the key the app is signed with. A **debug-signed** build sees a different ID from the release APK (observed on the Samsung test tablet on 22 Nov 2026).
- Therefore the handoff's "install over the existing app and confirm the licence is still valid" test must use **two release-signed APKs built by GitHub Actions**, installed one over the other. Compare the device ID and the licence or trial status before and after. The test tablet currently holds a debug-signed build, so it must be uninstalled first.

---

## 9. Current expense branch: inventory and rework plan

| File | Status on `daily-expenses` | Plan |
|---|---|---|
| `lib/models/expense.dart`, `expense.g.dart` | New, workbook-shaped (voucher, cost type, receipt status, asset tag) | **Replace** with the generic model (handoff 4.1) |
| `lib/models/expense_options.dart` | New, hardcoded workbook lists | **Remove** |
| `lib/pages/daily_expenses_page.dart` | New, cashier page with totals, any day, void | **Replace**: cashier sees only today's own entries, read-only. The full page moves into the Manager Backend |
| `lib/state/app_state_controller.dart` | Expense section added | **Replace** that section (no voucher, role, void reason and who) |
| `lib/main.dart` | Adapter registration, top-bar icon, ledger upload after backup | Adapter registration changes. The icon becomes the "Log Expense" entry, controlled by the manager setting. The ledger upload stays until phase 12 |
| `lib/pages/backend_page.dart` | Expense Export card, Backup Now uploads the ledger file | Both stay until phase 12. Later phases add Expenses, Finance Settings, Reports, Assets, Loans |
| `lib/services/expense_export_service.dart` | New, 14-column ledger export | Keep until phase 12, but see C1 |

---

## 10. Conflicts, gaps and decisions

- **C1 (decide before phase 4). The ledger export vs the new model.** The handoff says the ledger-format export stays "untouched" until the Reports are verified. That export needs a voucher number, a workbook cost type and category, a payment account, a receipt status and an asset tag. The reworked expense model (4.5) removes all of them. Options:
  - (a) A small temporary adapter built at export time and deleted in phase 12: voucher by creation order, cost type from the expense group, category through a manager-editable mapping table, payment account from "paid from", a default receipt status.
  - (b) Retire the ledger export at phase 4 and compare the new Reports with the workbook some other way (for example an offline comparison on exported data).
  - (c) Keep the old model alongside the new one. Rejected: it means double entry.
  - Recommendation: (a), kept small, only if the owner needs the workbook comparison during verification. Otherwise (b).
- **C2. CI builds only on pushes to `main`.** Handoff 2.4 wants the APK built after each phase. A trigger for the working branch (or a manual run trigger) would need an edit to the workflow YAML. Decide when the first APK from the branch is needed.
- **C3. Balance-receipt counter.** Proposal in Section 4: store it in the new finance settings box.
- **C4. Cashier role.** There is no login, so the role comes from the entry point (Section 4).
- **C5. Formulas without cached values** (Section 5).
- **C6. Handoff vs code drift.** The handoff mentions Google Sheets product sync. The code moved to a Drive-only product sheet at `a379635`. `CLAUDE.md` is out of date too (licensing is shown as not built; old OAuth scopes). Fix in the final phase.
- **C7. No real tests exist.** `test/widget_test.dart` is a placeholder, and `test/discount_code_util.dart` is not named `*_test.dart` so `flutter test` ignores it. Engine tests go in new `*_test.dart` files.
- **C8. "Paid from" list.** The handoff seeds Cash, Bank transfer, POS and Mobile money as a manager-editable list. Receipts keep their existing Cash, Transfer and POS options. The two lists are separate.
- **C9. No automatic Manager lock** (Section 6). Existing behaviour, out of scope.

---

## 11. Risks

- Adding fields to `Receipt` means regenerating `receipt.g.dart`. Prove it against a record written by the old adapter before any release, then run the upgrade test (handoff 8.3) with real data.
- Restore replaces boxes that are open at startup. This is the riskiest step. It needs the temporary-location, validate, swap order from the handoff, and a test that interrupts a restore.
- The 99-per-day sale limit stays as is. Balance receipts get their own counter.
- Large report ranges. Use an isolate and a progress indicator (handoff 2.2).

---

## 12. Plan

Order follows handoff Section 9. One commit per phase on the existing branch `daily-expenses`, one file at a time.

1. Audit findings. **This document.**
2. Display name: `AndroidManifest.xml`, `ios/Runner/Info.plist`, `lib/main.dart`.
3. Finance settings, new models and boxes, generic category seed (including the Not in P&L group).
4. Expense page rework (after C1 is decided).
5. Balance-payment fields and cashier mode.
6. Legacy matching, Unmatched list, link and "Settle with adjustment" actions.
7. Assets and depreciation.
8. Loans.
9. Report engine and unit tests.
10. Reports page and workbook builder.
11. Backup and restore.
12. Retire the ledger-format expense export, only after the Reports are verified.
13. Regression and upgrade tests, then update `CLAUDE.md` and the user manual.
