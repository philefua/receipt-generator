# Final Summary: Expense Tracking, Balance Payments, Financial Reports, Backup

Branch: `daily-expenses` (not yet merged to `main`). Date: 2026-11-27.

## 1. What was built (handoff phases)

| Phase | Result |
|---|---|
| 1 | Audit and written findings (`AUDIT_FINDINGS.md`) |
| 2 | Display name "Printiverse" (to be re-verified on a real install, see section 7) |
| 3 | Finance settings, new models and boxes, category seeds |
| 4 | Manager Expenses page, cashier Log Expense button. The old expense feature and the ledger workbook export were retired here (commit 4b) |
| 5 | Linked balance payments: new data fields, validation, cashier mode, balance receipt (own `-B` serial) |
| 6 | Legacy balance matching, Unmatched Balance Payments list, manual link, "Settle with adjustment" |
| 7 | Assets, depreciation engine, Manager Assets page |
| 8 | Loans, repayments (principal and interest), Manager Loans page |
| 9 | Pure-Dart report engine: sales, expenses, P&L, cashflow, receivables, assets, loans, filing figures, unmatched, notes |
| 10 | Report adapter, 11-sheet Excel workbook, Reports page with share |
| 11 | Backup and restore: central box list, versioned file, local file and Google Drive copy, safe restore with snapshot and rollback, integrity summary, reminders (7 days and financial-year end, also before a Reports export) |
| 12 | Already satisfied by phase 4b: no ledger export code or file remains. The receipt-history Excel export and its Drive upload are untouched |
| 13 | In progress: tablet checks, upgrade test, `CLAUDE.md` (done), user manual (pending) |

## 2. New files

`lib/features/finance/`: `finance_boxes`, `finance_repository`, `expense_repository`, `balance_repository`, `legacy_link_repository`, `settlement_repository`, `writeoff_totals`, `asset_repository`, `asset_rules`, `depreciation`, `loan_repository`, `loan_math`, `balance_receipt_view`, `balance_receipt_printing`, `report_period`, `report_inputs`, `report_data`, `report_engine`, `report_adapter`, `report_workbook`, `backup_service`.

`lib/features/finance/models/`: `asset`, `asset_category`, `expense`, `expense_category`, `finance_settings`, `loan`, `loan_transaction`, `receipt_link`, `stock_count` (each with generated `.g.dart`).

`lib/features/finance/screens/`: `expenses_page`, `expense_categories_page`, `cashier_expense_page`, `balance_payment_page`, `unmatched_balance_payments_page`, `settle_balances_page`, `assets_page`, `loans_page`, `loan_detail_page`, `finance_settings_page`, `reports_page`, `backup_page`.

`lib/features/finance/widgets/`: `finance_hub_card`, `log_expense_action`, `expense_form`, `asset_form`, `loan_form`, `repayment_form`, `balance_payment_button`, `balance_receipt_preview`.

Tests: `asset_depreciation_test`, `loan_math_test`, `report_fixtures`, `report_engine_test`, `report_sheets_test`, `report_adapter_test`, `report_workbook_test`, `backup_service_test`, `receipt_legacy_compat_test` (plus the earlier expense, balance and legacy-matching tests).

Docs: `AUDIT_FINDINGS.md`, `Claude.md` (updated), `FINAL_SUMMARY.md`.

## 3. Existing files modified

From `git diff --stat --diff-filter=M main HEAD -- lib android pubspec.yaml`: 12 files, 267 lines added, 14 removed. Each is a minimal hook point for a new feature. No existing typeId, field index or field type was changed.

| File | Lines | Reason |
|---|---|---|
| `android/app/src/main/AndroidManifest.xml` | 1 | Launcher label changed to "Printiverse". The `applicationId`, signing and licensing are untouched. |
| `lib/main.dart` | 12 | Registers the finance adapters, opens the finance boxes, applies a staged restore before any box opens, opens the backup meta box, and adds the Log Expense action to the top bar. |
| `lib/models/receipt.dart`, `receipt.g.dart` | 16, 10 | New nullable, higher-index fields for balance-payment data (receipt type and the linked original). Receipts saved earlier still read back as sales (covered by `receipt_legacy_compat_test`). |
| `lib/pages/backend_page.dart` | 13 | Adds the Finance card to the Manager Backend. |
| `lib/pages/frontend_page.dart` | 3 | One import and one `BalancePaymentButton` placed under the header on the cashier screen. The sale form and everything below it are unchanged. |
| `lib/pages/receipt_history_page.dart` | 25 | Shows balance-payment receipts distinctly and keeps reprint working for them. |
| `lib/services/thermal_printer_service.dart` | 6 | One import and one early branch: when `receipt.isBalancePayment` it uses the balance receipt template. Sales run the original code unchanged. |
| `lib/services/whatsapp_share_service.dart` | 11 | WhatsApp text for balance receipts. |
| `lib/state/app_state_controller.dart` | 4 | Adds `notifyReceiptsChanged()`, a one-line method that lets the finance feature tell the screens the receipts box changed after it saves a balance receipt. No existing logic was altered. |
| `lib/services/google_drive_service.dart` | 174 | Added `uploadBackupFile`, `listBackupFiles`, `downloadFile` and their result classes. The Excel upload and product Sheet methods are unchanged. |
| `pubspec.yaml` | 5 | Added `file_picker`; `share_plus` pinned to 12.x to resolve a `win32` conflict. |

The reasons for `frontend_page.dart`, `thermal_printer_service.dart` and `app_state_controller.dart` were checked against the actual diffs. The others are taken from the phase plan and the size of each change; check any of them with `git diff main HEAD -- <file>`.

## 4. Hive typeIds and boxes

New typeIds: 6 FinanceSettings, 7 ExpenseCategory, 8 AssetCategory, 9 ReceiptLink, 10 StockCount, 11 Asset, 12 Loan, 13 LoanTransaction, 14 Expense (reworked). typeId 5 (old expense) is retired and never reused. Next free: 15.

New boxes: `finance_settings_box`, `expense_categories_box`, `asset_categories_box`, `receipt_links_box`, `stock_counts_box`, `assets_box`, `loans_box`, `loan_transactions_box`, `finance_expenses_box`, and `backup_meta_box` (strings, not backed up). The licence box is excluded from backups.

## 5. Test results

`flutter analyze`: no issues. `flutter test`: 290 tests passing at the last run, including 10 backup tests (round trip, refused files, newer-version refusal, integrity failure, failed-restore rollback, unconfirmed restore ignored, four reminder rules).

Tablet (Galaxy Tab A8): backup file, Google Drive backup, Google Drive restore, Reports build and share to WhatsApp, and the other checks listed by the owner passed. The upgrade test over a real install and the full checklist in `Claude.md` section 8.2 are still to be recorded.

## 6. Deviations from the handoff

1. **Backup format**: one JSON file holding each box's own Hive file (base64, with SHA-256 and a checksum) instead of per-record JSON. This keeps every record byte-identical and needs no hand-written converters.
2. **Restore needs an app restart.** It is staged and verified while the app runs and applied at the next launch, before any box opens, with a snapshot and rollback. This replaces "swap while running".
3. **Restore confirmation** is the Manager lock plus typing RESTORE. No second password prompt was added.
4. **Drive copy of the backup** was added after the local file, at the owner's request. It only lists files this app uploaded.
5. **Reminder rule** is 7 days or a new financial year since the last backup.
6. **Phase 12** was completed early, in phase 4b, so there was no old export left to compare Reports against. Verification is against the Expenses page totals.
7. **Reports header**: the Tax ID typed in Finance Settings is printed in the report header (blank if not entered). The app version prints blank because the project has no `package_info_plus`.
8. **Typed-box bug** in the first backup version (found on the tablet, fixed). Tests cannot reproduce typed boxes on a device, so a tablet check is part of the checklist.
9. **Cleanup pending**: stray files committed earlier (two `.patch` files, `apply_phase4b.ps1`, `apply_phase5.ps1`) can be removed in a separate commit.

## 7. Still to do

- Finish the manual regression checklist and the upgrade test over an install with real data (same signing key).
- Confirm the "Printiverse" launcher name shows and the existing licence is still valid after installing over an existing app.
- Update the user manual.
- Merge `daily-expenses` into `main` only after the above pass.
