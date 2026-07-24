# CLAUDE.md — Receipt Generator: Architectural Blueprint

> Internal reference document for AI-assisted development on this project.
> Business: Printiverse (custom digital printing, Benin City, Edo State, Nigeria)

---

## 1. Project Overview and Tech Stack

### 1.1 What This App Is

Receipt Generator is a single Flutter application with two integrated sides:

- **Cashier Frontend** — open point-of-sale screen used to record sales, print/share receipts.
- **Manager Backend** — password-protected admin area for business configuration, product management, sales history export, and remote cloud sync.

Target devices: Android phones and tablets (primary test device: Samsung Galaxy Tab A8). Responsive layout adapts between phone (stacked) and tablet (side-by-side) breakpoints.

### 1.2 Core Tech Stack


|
 Layer 
|
 Technology 
|
|
---
|
---
|
|
 Framework 
|
 Flutter (Dart), Material 3 
|
|
 State management 
|
`provider`
 (single 
`ChangeNotifier`
: 
`AppStateController`
) 
|
|
 Local persistence 
|
`hive`
 / 
`hive_flutter`
 (NoSQL, boxes per data type) 
|
|
 Printing 
|
`flutter_classic_bluetooth`
 (RFCOMM/SPP) + 
`esc_pos_utils_plus`
 (ESC/POS byte generation) 
|
|
 Sharing 
|
`share_plus`
 (Excel export), 
`url_launcher`
 (WhatsApp 
`wa.me`
 deep links) 
|
|
 Permissions 
|
`permission_handler`
|
|
 Excel generation 
|
`excel`
|
|
 Cloud backup/sync 
|
`google_sign_in`
, 
`googleapis`
, 
`googleapis_auth`
, 
`http`
|
|
 Utility 
|
`intl`
, 
`uuid`
, 
`crypto`
, 
`path_provider`
|
|
 Build/CI 
|
 GitHub Actions (
`ubuntu-latest`
 runner) 
|

### 1.3 Local Development Environment (VS Code)

- **Flutter SDK**: installed locally at `C:\flutter\flutter` (Windows), added to PATH via `%FLUTTER_HOME%\bin`.
- **Java/JDK**: uses Android Studio's bundled JBR at `C:\Program Files\Android\Android Studio\jbr`, referenced via `JAVA_HOME`.
- **Android SDK**: installed via Android Studio; `sdkmanager` licenses accepted; `cmdline-tools` component installed.
- **Git**: installed separately (not bundled with VS Code); user identity configured via `git config --global user.name/user.email`.
- Local builds are fully supported (`flutter build apk --release`), though the canonical/production build path is GitHub Actions.
- **Editing workflow convention**: full-file replacements preferred over line-level diffs, especially for YAML (whitespace-sensitive) and Dart files, to avoid indentation/drift errors.

### 1.4 GitHub Setup

- **Repository**: `philefua/receipt-generator` (public repo on GitHub).
- **CI/CD**: `.github/workflows/build_apk.yml` — triggers on push to `main`/`master`, builds a signed release APK, uploads as a workflow artifact.
- **Signing**: dedicated permanent release keystore (Ed25519/RSA via `keytool`), stored **only** as base64 inside GitHub Actions repository secrets (never committed to the repo). Workflow decodes it during build via `grep -v "CERTIFICATE" | tr -d '\r' | base64 --decode` to strip Windows `certutil` wrapper artifacts before decoding on the Ubuntu runner.
- **Secrets in use**: `RELEASE_KEYSTORE_BASE64_V2`, `RELEASE_KEYSTORE_PASSWORD_V2`, `RELEASE_KEY_ALIAS`.
- **`.gitignore`**: excludes `/secrets/` (local keystore storage folder), build artifacts, IDE folders.
- Distribution model: sideloaded APK (not published to Google Play), installed manually per device.

---

## 2. API Endpoints and Integration

### 2.1 Google Cloud Project

- One Google Cloud project backs this app, with **Google Drive API** and **Google Sheets API** enabled.
- **OAuth consent screen**: External user type, Testing publishing status (not verified/public) — restricted to explicitly added test-user email addresses.
- **OAuth scopes requested**:
  - `https://www.googleapis.com/auth/drive.file` — access limited to files the app itself creates (not full Drive access).
  - `https://www.googleapis.com/auth/spreadsheets` — read/write access to Sheets.
- **Android OAuth Client**: registered under package `com.example.receipt_generator`, tied to the release keystore's SHA-1 fingerprint (verification is certificate-based, not a bundled config file).

### 2.2 Authentication Flow

- `google_sign_in` package handles the interactive sign-in UI (manager taps "Connect Google Account" in Manager Backend).
- `trySilentSignIn()` is attempted first on every app launch to restore a previously-connected session without prompting — enables fully unattended daily automation.
- Authenticated requests are made via a custom `http.BaseClient` subclass (`_GoogleAuthClient` / `_SheetsAuthClient`) that injects the signed-in account's `authHeaders` into every outgoing request, bridging `google_sign_in` to the `googleapis` package's expected `http.Client` interface.

### 2.3 Google Drive Integration — `lib/services/google_drive_service.dart`

- **Purpose**: uploads the receipt history Excel export to the manager's connected Drive account.
- **Key method**: `uploadExcelBackup({bytes, fileName})` → `drive.DriveApi(client).files.create(...)` with MIME type `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`.
- Each call creates a **new** file (no overwrite/versioning logic); retention/cleanup of older backups is not currently automated.

### 2.4 Google Sheets Integration — `lib/services/google_sheets_service.dart`

- **Purpose**: reads a manager-maintained Google Sheet (Product Name in column A, Unit Price in column B) to remotely sync preset products.
- **Key method**: `fetchProducts({sheetIdOrUrl, range: 'A:B'})` → `sheets.SheetsApi(client).spreadsheets.values.get(sheetId, range)`.
- `extractSheetId()` accepts either a raw Sheet ID or a full Google Sheets URL pasted by the manager.
- Rows with a non-numeric price column (e.g. header rows) are silently skipped rather than failing the whole sync.
- **Critical constraint**: the linked document must be a *native* Google Sheet — an uploaded `.xlsx` file on Drive cannot be read by this API and returns a 400 error (`"document must not be an office file"`).

### 2.5 Sync Orchestration

- `AppStateController.replaceProductPresetsFromSync()` reconciles fetched Sheet rows against local presets: matches by case-insensitive name, updates prices for matches, adds new presets for unmatched names, and **soft-deletes** (deactivates) local presets no longer present in the Sheet — never hard-deletes, consistent with the rest of the app's deletion philosophy.
- **Automatic scheduling**: on every app launch (`RootShell.initState()` → `_runAutoSyncIfDue()`), the app silently attempts sign-in, then independently checks `controller.isBackupDue` and `controller.isSyncDue` (both gated on a rolling 24-hour window since `lastBackupAt`/`lastSyncAt`, persisted in `BusinessSettings`). All failures are caught and silently ignored — background automation must never interrupt or alarm the cashier.
- **Manual triggers**: "Backup Now" and "Sync Now" buttons in the Manager Backend's Google Sync card call the same underlying service methods used by the automatic path.

### 2.6 WhatsApp Integration (non-Google, no API key)

- Uses the public `wa.me` deep-link scheme via `url_launcher`: `https://wa.me/{sanitizedNumber}?text={encodedMessage}`.
- No WhatsApp Business API / Cloud API integration — this is a client-side deep link only, requiring the WhatsApp app installed on the device.
- Used for: (a) sharing a formatted multi-line receipt summary to the customer, (b) planned future use for licensing payment requests (see Section 5).

---

## 3. Folder and File Structure

receipt-generator/ # repo root
├── .github/
│ └── workflows/
│ └── build_apk.yml # CI: build + sign release APK
├── android/
│ ├── app/
│ │ ├── build.gradle.kts # signingConfigs (release keystore wiring)
│ │ ├── receipt_generator_release.keystore # decoded at CI-time only, gitignored locally
│ │ └── src/main/
│ │ ├── AndroidManifest.xml # permissions: Bluetooth, storage, internet
│ │ └── kotlin/.../MainActivity.kt
│ └── build.gradle.kts
├── secrets/ # LOCAL ONLY — gitignored
│ └── receipt_generator_release.keystore
├── lib/
│ ├── main.dart # app entry, RootShell, auto-sync trigger
│ ├── models/
│ │ ├── business_settings.dart # Hive: business info, currency, Sheet ID, sync timestamps
│ │ ├── product_preset.dart # Hive: preset products (name, price, active flag)
│ │ ├── cart_item.dart # transient (non-Hive) working cart line
│ │ └── receipt.dart # Hive: immutable Receipt + ReceiptItem
│ ├── state/
│ │ └── app_state_controller.dart # single ChangeNotifier — all business logic
│ ├── services/
│ │ ├── thermal_printer_service.dart # Bluetooth connect + ESC/POS byte building/sending
│ │ ├── whatsapp_share_service.dart # wa.me deep-link receipt sharing
│ │ ├── google_drive_service.dart # Drive sign-in + backup upload
│ │ └── google_sheets_service.dart # Sheets product sync
│ ├── pages/
│ │ ├── frontend_page.dart # Cashier screen (Scaffold + dialogs)
│ │ ├── backend_page.dart # Manager screen (lock screen + all admin cards)
│ │ ├── printer_setup_page.dart # Bluetooth device list + connect UI
│ │ ├── receipt_history_page.dart # history list + detail/reprint view
│ │ └── product_picker_page.dart # full-screen A–Z searchable product picker
│ ├── widgets/
│ │ └── receipt_preview_widget.dart # shared visual receipt renderer (on-screen + pre-print)
│ └── utils/
│ └── discount_code_util.dart # deterministic receipt serial code generator
├── test/
│ └── widget_test.dart # placeholder test
├── pubspec.yaml # all dependencies (see Section 1.2)
├── .gitignore # excludes /secrets/, build artifacts
└── analysis_options.yaml


### 3.1 Key File Responsibilities

| File | Responsibility |
|---|---|
| `app_state_controller.dart` | Single source of truth: settings CRUD, product CRUD + sync merge, cart math, receipt finalization (write-once), history queries, backup/sync due-checks |
| `receipt.dart` | Defines the **immutable** `Receipt`/`ReceiptItem` model — no update/delete path exists anywhere in the controller by design |
| `business_settings.dart` | Single Hive record holding all configurable business state, including `googleSheetId`, `lastBackupAt`, `lastSyncAt` |
| `thermal_printer_service.dart` | Owns the only `BtcConnection` instance; builds full ESC/POS byte stream (header, items, totals, coupon, balance owed, footnote) independent of transport plugin |
| `google_drive_service.dart` / `google_sheets_service.dart` | Each owns its own authenticated `http.Client` bridge; no shared auth object — `GoogleDriveService.instance.currentAccountForAuth` is exposed for `google_sheets_service.dart` to reuse the same signed-in session |

---

## 4. Brief Requirements and Rules

### 4.1 Core Features (implemented)

- **Cashier Frontend**: business header display, customer form (name + international-format WhatsApp number, validated `+\d{8,15}`), item entry (preset picker or manual), per-receipt discount %, optional coupon reference (record-keeping only, never affects receipt code), partial deposit + auto-computed balance owed, payment method (Cash/Transfer/POS), Process Receipt (locked until valid), post-checkout Print + Share (independent, non-blocking actions).
- **Product Picker**: full-screen, alphabetically sorted, live search box, tappable A–Z jump strip (unavailable letters greyed out); replaces the former inline dropdown.
- **Manager Backend**: password-gated (SHA-256 hashed, default `admin123` on first install), Business Information form (name, currency symbol, address, socials, footnote), Change Password (requires re-entering current password even though already unlocked), Preset Products (single Add, Edit, soft-Delete, and Bulk Import via `Name, Price` per-line paste with per-line error tolerance), Excel history export (via native share sheet, not direct file-system writes), Google Sync card (connect/disconnect, Backup Now, Sheet link + Sync Now).
- **Receipt History**: read-only, newest-first, tap for full detail, Reprint action reuses the same print pipeline as checkout.
- **Printer Setup**: standalone screen; lists OS-paired devices only (no active BLE/Classic scanning); manual Connect per device; runtime `bluetoothConnect` permission requested (not `bluetoothScan`/location — deliberately narrowed after this over-broad request caused false permission denials).
- **Immutability guarantee**: once a `Receipt` is written via `finalizeAndSaveReceipt()`, no code path anywhere can edit or delete it. Product/price edits after the fact never retroactively alter past receipts (frozen `ReceiptItem` snapshots).

### 4.2 Coding Preferences / Conventions Established in This Project

- **Full-file replacements preferred** over targeted line edits for any file previously affected by drift, corruption, or duplication — especially `.gitignore`, YAML workflow files, and any Hive model file.
- **One file, one instruction at a time** during active debugging sessions — avoid bundling multiple file changes into a single exchange when troubleshooting.
- Always run `flutter analyze` locally before commit/push; treat `0 issues found` as the gate before shipping.
- Hive field additions always require a `build_runner` regeneration pass (`dart run build_runner build --delete-conflicting-outputs`) **after** the model AND controller changes are both in place, not before.
- Never assume a workaround exists for exact YAML indentation — GitHub Actions workflow files have repeatedly broken from single-space misalignment; verify via full-file paste-back when uncertain.
- Sensitive material (keystores, encoded secrets, private keys) must **never** be pasted into chat after initial generation — store via password manager / GitHub Secrets UI only. Any material that is accidentally exposed is treated as permanently compromised and regenerated, rather than relying on git history scrubbing.
- Soft-delete (deactivate) is the standing pattern for all "remove" actions on mutable entities (products) — hard deletion is never used, to protect historical data integrity.
- Silent/background automation (auto-backup, auto-sync) must never surface errors to the cashier UI — failures are caught and swallowed; manual buttons remain the user-facing fallback and diagnostic path.
- New third-party package versions should be checked against `flutter pub outdated` when a plugin-level bug is suspected — this resolved two real production bugs in this project (`share_plus` Android result-tracking crash; general practice of preferring an upstream fix over a workaround once one becomes available).

### 4.3 Known Platform Constraints (accepted, not defects)

- WhatsApp sharing cannot pre-attach an image to a specific contact via any public API — only pre-filled text via `wa.me` is reliable; this is why the Share feature sends a formatted text summary rather than a receipt image.
- A fully offline app cannot achieve absolute tamper-proof time enforcement — device clocks are user-controlled. Practical mitigation only (see Section 5).
- Google apps in "Testing" publish status show an "unverified app" warning to test users and are hard-limited to explicitly listed test-user emails — expected, not a bug.
- Bluetooth Classic (SPP) connection reliability varies meaningfully by printer hardware/firmware; `flutter_classic_bluetooth` was adopted after `print_bluetooth_thermal` and `flutter_bluetooth_serial` both failed against the project's actual test printer (Xprinter XP-P300) or the build toolchain (`flutter_bluetooth_serial`'s `jcenter()` dependency is incompatible with modern AGP).

---

## 5. Next Intended Plan (Not Yet Implemented)

**Offline Trial & Licensing System** — in early design/scaffolding only as of this document. Intended architecture (subject to change):

- 35-day trial window from first launch, anchored via a locally-stored install timestamp.
- Anti-rollback "high-water mark" clock: the app never accepts a device time earlier than the latest time it has already observed, defeating simple date-backdating.
- Device-bound licensing (not account/email-bound) using Android's hardware-level `ANDROID_ID`, obtained via a native platform channel — ensures uninstall/reinstall or switching Google accounts cannot reset a trial or bypass an expired license.
- One-time internet-connected check at initial trial activation only (not ongoing) to register the device ID against a lightweight registry (the existing Google Sheet integration), closing the most common reinstall-based workaround.
- Cryptographically signed activation codes (Ed25519 keypair — public key embedded in-app for verification only; private signing key held exclusively by the app owner, never committed to the repository) encoding device ID + plan tier + expiry, generated via a small standalone offline tool outside the app.
- Full-screen lockout UI on expiry, with a WhatsApp deep-link payment request (device ID + requested plan pre-filled) and an activation code entry field.
- Plans: 1 month / 6 months / 1 year / lifetime.

This feature is intentionally excluded from the "implemented" sections above and should be treated as a distinct, not-yet-built module when referenced in future work.