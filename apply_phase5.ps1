# Phase 5: linked balance payments. Edits your existing files for the new feature.
# Run from the project folder (the one containing pubspec.yaml):
#   powershell -ExecutionPolicy Bypass -File .\apply_phase5.ps1
#
# Safe by design: every edit is computed in memory first. If any expected
# text is not found exactly as expected, NOTHING is changed.
$ErrorActionPreference = 'Stop'

if (-not (Test-Path 'pubspec.yaml')) { throw 'Run this from the project folder (pubspec.yaml not found).' }
$dirty = git status --porcelain --untracked-files=no
if ($dirty) { throw "You have uncommitted changes. Commit or stash them first:`n$dirty" }

function Read-Source([string]$path) {
  if (-not (Test-Path $path)) { throw "File not found: $path" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  if ($bom) { $text = $text.Substring(1) }
  return @{ Text = $text; Bom = $bom }
}

function Edit-Text([string]$text, [string]$file, [string]$label, [string]$pattern, [string]$replacement, [int]$expected) {
  $count = [regex]::Matches($text, $pattern).Count
  if ($count -ne $expected) {
    throw "[$file] '$label': expected $expected match(es) but found $count. Nothing was changed. Send this message back."
  }
  return [regex]::Replace($text, $pattern, $replacement)
}

function Write-Source([string]$path, [string]$text, [bool]$bom) {
  $enc = New-Object System.Text.UTF8Encoding($bom)
  [System.IO.File]::WriteAllText($path, $text, $enc)
}

$results = @{}


# ---- lib/models/receipt.dart ----
$file = 'lib/models/receipt.dart'
$src = Read-Source $file
$t = $src.Text
$p = @'
(?m)^  @HiveField\(14\)(\r?\n)  final double balanceOwed;(\r?\n)
'@
$r = @'
  @HiveField(14)${1}  final double balanceOwed;${1}${1}  /// 'sale' for every normal sale, or 'balance_payment'. Records saved before${1}  /// balance payments existed have no value stored and read back as a sale.${1}  @HiveField(15, defaultValue: 'sale')${1}  final String receiptType;${1}${1}  /// For a balance payment: the receipt number of the original sale.${1}  @HiveField(16)${1}  final String? linkedReceiptId;${1}${1}  static const String typeSale = 'sale';${1}  static const String typeBalancePayment = 'balance_payment';${1}${1}  bool get isBalancePayment => receiptType == typeBalancePayment;${1}
'@
$t = Edit-Text $t $file 'add receiptType and linkedReceiptId fields' $p $r 1
$p = @'
(?m)^    this\.balanceOwed = 0,(\r?\n)  \}\);
'@
$r = @'
    this.balanceOwed = 0,${1}    this.receiptType = 'sale',${1}    this.linkedReceiptId,${1}  });
'@
$t = Edit-Text $t $file 'add constructor parameters' $p $r 1
$results[$file] = @{ Text = $t; Bom = $src.Bom }

# ---- lib/pages/frontend_page.dart ----
$file = 'lib/pages/frontend_page.dart'
$src = Read-Source $file
$t = $src.Text
$p = @'
(?m)^import '\.\./models/product_preset\.dart';(\r?\n)
'@
$r = @'
import '../features/finance/widgets/balance_payment_button.dart';${1}import '../models/product_preset.dart';${1}
'@
$t = Edit-Text $t $file 'import balance button' $p $r 1
$p = @'
(?m)^                  _buildHeader\(context\),(\r?\n)                  const SizedBox\(height: 12\),(\r?\n)                  _buildCustomerForm\(\),
'@
$r = @'
                  _buildHeader(context),${1}                  const SizedBox(height: 12),${1}                  const BalancePaymentButton(),${1}                  const SizedBox(height: 12),${1}                  _buildCustomerForm(),
'@
$t = Edit-Text $t $file 'add Balance Payment button under header' $p $r 1
$results[$file] = @{ Text = $t; Bom = $src.Bom }

# ---- lib/pages/receipt_history_page.dart ----
$file = 'lib/pages/receipt_history_page.dart'
$src = Read-Source $file
$t = $src.Text
$p = @'
(?m)^import '\.\./models/receipt\.dart';(\r?\n)
'@
$r = @'
import '../features/finance/balance_receipt_view.dart';${1}import '../features/finance/balance_repository.dart';${1}import '../features/finance/widgets/balance_receipt_preview.dart';${1}import '../models/receipt.dart';${1}
'@
$t = Edit-Text $t $file 'imports' $p $r 1
$p = @'
(?m)^    final dateFormat = DateFormat\('yyyy-MM-dd  HH:mm'\);(\r?\n)
'@
$r = @'
    final dateFormat = DateFormat('yyyy-MM-dd  HH:mm');${1}    final outstandingByCode = BalanceRepository.outstandingByCode(receipts);${1}
'@
$t = Edit-Text $t $file 'compute outstanding once per build' $p $r 1
$p = @'
(?s)                    subtitle: Text\(\r?\n                      '\$\{receipt\.customerName\.isNotEmpty \? receipt\.customerName : 'Walk-in customer'\}\\n'\r?\n                      '\$\{dateFormat\.format\(receipt\.issuedAt\)\} \u2022 \$\{receipt\.paymentMethod\}',(\r?\n)                    \),
'@
$r = @'
                    subtitle: Text(${1}                      historySubtitle(${1}                        receipt: receipt,${1}                        dateText: dateFormat.format(receipt.issuedAt),${1}                        currency: currency,${1}                        outstandingByCode: outstandingByCode,${1}                      ),${1}                    ),
'@
$t = Edit-Text $t $file 'history subtitle' $p $r 1
$p = @'
(?m)^          child: ReceiptPreviewWidget\((\r?\n)            receipt: widget\.receipt,(\r?\n)            business: controller\.settings,(\r?\n)          \),
'@
$r = @'
          child: widget.receipt.isBalancePayment${1}              ? BalanceReceiptPreview(${1}                  receipt: widget.receipt,${1}                  business: controller.settings,${1}                )${1}              : ReceiptPreviewWidget(${1}                  receipt: widget.receipt,${1}                  business: controller.settings,${1}                ),
'@
$t = Edit-Text $t $file 'detail preview branch' $p $r 1
$results[$file] = @{ Text = $t; Bom = $src.Bom }

# ---- lib/services/thermal_printer_service.dart ----
$file = 'lib/services/thermal_printer_service.dart'
$src = Read-Source $file
$t = $src.Text
$p = @'
(?m)^import '\.\./models/receipt\.dart';(\r?\n)
'@
$r = @'
import '../features/finance/balance_receipt_printing.dart';${1}import '../models/receipt.dart';${1}
'@
$t = Edit-Text $t $file 'import balance printing' $p $r 1
$p = @'
(?m)^    final profile = await CapabilityProfile\.load\(\);(\r?\n)
'@
$r = @'
    // Balance payments have their own template (phase 5). Sales are unchanged.${1}    if (receipt.isBalancePayment) {${1}      return buildBalanceReceiptBytes(receipt: receipt, business: business);${1}    }${1}${1}    final profile = await CapabilityProfile.load();${1}
'@
$t = Edit-Text $t $file 'balance template branch' $p $r 1
$results[$file] = @{ Text = $t; Bom = $src.Bom }

# ---- lib/services/whatsapp_share_service.dart ----
$file = 'lib/services/whatsapp_share_service.dart'
$src = Read-Source $file
$t = $src.Text
$p = @'
(?m)^import '\.\./models/receipt\.dart';(\r?\n)
'@
$r = @'
import '../features/finance/balance_receipt_view.dart';${1}import '../models/receipt.dart';${1}
'@
$t = Edit-Text $t $file 'import balance view' $p $r 1
$p = @'
(?m)^    final buffer = StringBuffer\(\);(\r?\n)    final currencySymbol = business\.currencySymbol;(\r?\n)
'@
$r = @'
    // Balance payments have their own message (phase 5). Sales are unchanged.${1}    if (receipt.isBalancePayment) {${1}      return BalanceReceiptView.fromReceipt(${1}        receipt,${1}        businessName: business.businessName,${1}        currency: business.currencySymbol,${1}        footnote: business.footnote,${1}      ).whatsappMessage();${1}    }${1}${1}    final buffer = StringBuffer();${1}    final currencySymbol = business.currencySymbol;${1}
'@
$t = Edit-Text $t $file 'balance message branch' $p $r 1
$results[$file] = @{ Text = $t; Bom = $src.Bom }

# ---- lib/state/app_state_controller.dart ----
$file = 'lib/state/app_state_controller.dart'
$src = Read-Source $file
$t = $src.Text
$p = @'
(?m)^  Receipt\? findReceiptByCode\(String code\) \{(\r?\n)
'@
$r = @'
  /// Lets the finance feature tell the screens that the receipts box changed${1}  /// (it saves balance receipts itself).${1}  void notifyReceiptsChanged() => notifyListeners();${1}${1}  Receipt? findReceiptByCode(String code) {${1}
'@
$t = Edit-Text $t $file 'add notifyReceiptsChanged' $p $r 1
$results[$file] = @{ Text = $t; Bom = $src.Bom }

# ---- all edits matched: now write the files ----
foreach ($key in $results.Keys) { Write-Source $key $results[$key].Text $results[$key].Bom; Write-Host "Edited  $key" }

# ---- regenerate the Hive adapter for Receipt (new fields 15 and 16) ----
Write-Host ''
Write-Host 'Regenerating Hive adapters (this takes a minute)...'
dart run build_runner build --delete-conflicting-outputs
if ($LASTEXITCODE -ne 0) {
  Write-Host 'build_runner failed. Send the output above back.' -ForegroundColor Red
  exit 1
}
if (-not (Select-String -Path 'lib\models\receipt.g.dart' -Pattern 'fields\[16\]' -Quiet)) {
  Write-Host 'receipt.g.dart does not contain the new fields. Send this message back.' -ForegroundColor Red
  exit 1
}
Write-Host ''
Write-Host 'Done. Next: flutter analyze ; flutter test' -ForegroundColor Green

