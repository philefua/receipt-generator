# Phase 4b: wire up the new expense feature and retire the old one.
# Run from the project folder (the one containing pubspec.yaml):
#   powershell -ExecutionPolicy Bypass -File .\apply_phase4b.ps1
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


# ---- lib/main.dart ----
$file = 'lib/main.dart'
$src = Read-Source $file
$t = $src.Text
$p = @'
(?m)^import 'models/expense\.dart';\r?\n
'@
$r = ''
$t = Edit-Text $t $file 'remove import models/expense' $p $r 1
$p = @'
(?m)^import 'pages/daily_expenses_page\.dart';\r?\n
'@
$r = ''
$t = Edit-Text $t $file 'remove import daily_expenses_page' $p $r 1
$p = @'
(?m)^import 'services/expense_export_service\.dart';\r?\n
'@
$r = ''
$t = Edit-Text $t $file 'remove import expense_export_service' $p $r 1
$p = @'
(?m)^import 'features/finance/finance_boxes\.dart';(\r?\n)
'@
$r = @'
import 'features/finance/finance_boxes.dart';${1}import 'features/finance/widgets/log_expense_action.dart';${1}
'@
$t = Edit-Text $t $file 'add import log_expense_action' $p $r 1
$p = @'
(?m)^  Hive\.registerAdapter\(ExpenseAdapter\(\)\);\r?\n
'@
$r = ''
$t = Edit-Text $t $file 'remove old adapter registration' $p $r 1
$p = @'
(?m)^          await _backupExpensesQuietly\(controller\);\r?\n
'@
$r = ''
$t = Edit-Text $t $file 'remove ledger upload call' $p $r 1
$p = @'
(?s)  /// Uploads the expense report \(same layout.*?(?=  Future<Uint8List> _buildHistoryExcelBytes)
'@
$r = ''
$t = Edit-Text $t $file 'remove _backupExpensesQuietly method' $p $r 1
$p = @'
(?s)          IconButton\(\r?\n            tooltip: 'Daily Expenses',.*?\r?\n          \),(\r?\n)
'@
$r = @'
          const LogExpenseAction(),${1}
'@
$t = Edit-Text $t $file 'swap top-bar icon for Log Expense' $p $r 1
$results[$file] = @{ Text = $t; Bom = $src.Bom }

# ---- lib/pages/backend_page.dart ----
$file = 'lib/pages/backend_page.dart'
$src = Read-Source $file
$t = $src.Text
$p = @'
(?m)^import '\.\./services/expense_export_service\.dart';\r?\n
'@
$r = ''
$t = Edit-Text $t $file 'remove import expense_export_service' $p $r 1
$p = @'
(?m)^  bool _isExportingExpenses = false;\r?\n
'@
$r = ''
$t = Edit-Text $t $file 'remove _isExportingExpenses field' $p $r 1
$p = @'
(?s)  Future<void> _exportExpensesToExcel\(BuildContext context\) async \{.*?(?=  @override\r?\n  Widget build\(BuildContext context\) \{\r?\n    if \(!_unlocked\))
'@
$r = ''
$t = Edit-Text $t $file 'remove _exportExpensesToExcel' $p $r 1
$p = @'
(?m)^ +_buildExpenseExportCard\(context\),\r?\n +const SizedBox\(height: 16\),\r?\n
'@
$r = ''
$t = Edit-Text $t $file 'remove Expense Export card usages' $p $r 2
$p = @'
(?s)  Widget _buildExpenseExportCard\(BuildContext context\) \{.*?(?=  Widget _buildExportCard\(BuildContext context\) \{)
'@
$r = ''
$t = Edit-Text $t $file 'remove _buildExpenseExportCard' $p $r 1
$p = @'
(?m)^    final controller = context\.read<AppStateController>\(\);\r?\n(?=    setState\(\(\) => _isBackingUp = true\);)
'@
$r = ''
$t = Edit-Text $t $file 'remove unused controller in Backup Now' $p $r 1
$p = @'
(?s)      // The expense report goes up right after the sales backup\..*?\r?\n      \}\r?\n\r?\n(?=      if \(!mounted\) return;)
'@
$r = ''
$t = Edit-Text $t $file 'remove expense report upload in Backup Now' $p $r 1
$p = @'
(?m)^      var message = result\.message;
'@
$r = @'
      final message = result.message;
'@
$t = Edit-Text $t $file 'message final' $p $r 1
$p = @'
(?m)^      var success = result\.success;
'@
$r = @'
      final success = result.success;
'@
$t = Edit-Text $t $file 'success final' $p $r 1
$results[$file] = @{ Text = $t; Bom = $src.Bom }

# ---- lib/state/app_state_controller.dart ----
$file = 'lib/state/app_state_controller.dart'
$src = Read-Source $file
$t = $src.Text
$p = @'
(?m)^import '\.\./models/expense\.dart';\r?\n
'@
$r = ''
$t = Edit-Text $t $file 'remove import expense' $p $r 1
$p = @'
(?m)^import '\.\./models/expense_options\.dart';\r?\n
'@
$r = ''
$t = Edit-Text $t $file 'remove import expense_options' $p $r 1
$p = @'
(?m)^  static const String _expensesBoxName = 'expenses_box';\r?\n
'@
$r = ''
$t = Edit-Text $t $file 'remove _expensesBoxName' $p $r 1
$p = @'
(?m)^  late final Box<Expense> _expensesBox;\r?\n
'@
$r = ''
$t = Edit-Text $t $file 'remove _expensesBox field' $p $r 1
$p = @'
(?m)^    _expensesBox = await Hive\.openBox<Expense>\(_expensesBoxName\);\r?\n
'@
$r = ''
$t = Edit-Text $t $file 'remove _expensesBox open' $p $r 1
$p = @'
(?s)  // -{20,}\r?\n  // Daily expense record.*?(?=  Receipt\? findReceiptByCode)
'@
$r = ''
$t = Edit-Text $t $file 'remove daily expense section' $p $r 1
$results[$file] = @{ Text = $t; Bom = $src.Bom }

# ---- all edits matched: now write the files ----
foreach ($key in $results.Keys) { Write-Source $key $results[$key].Text $results[$key].Bom; Write-Host "Edited  $key" }

# ---- remove the old expense files ----
$old = @('lib/pages/daily_expenses_page.dart', 'lib/services/expense_export_service.dart', 'lib/models/expense.dart', 'lib/models/expense.g.dart', 'lib/models/expense_options.dart')
foreach ($d in $old) { if (Test-Path $d) { git rm -q -- $d; Write-Host "Removed $d" } else { Write-Host "(already gone) $d" } }

# ---- leftovers check ----
$left = Get-ChildItem -Path lib, test -Recurse -Filter *.dart | Select-String -Pattern 'ExpenseExportService|DailyExpensesPage|exportableExpenses|expense_options|models/expense\.dart|ExpenseOptions'
if ($left) {
  Write-Host ''
  Write-Host 'These places still mention the old expense code. Send this list back:' -ForegroundColor Yellow
  $left | ForEach-Object { Write-Host ("  " + $_.Path + ":" + $_.LineNumber + "  " + $_.Line.Trim()) }
} else {
  Write-Host ''
  Write-Host 'No leftover references to the old expense code.' -ForegroundColor Green
}
Write-Host ''
Write-Host 'Done. Next: flutter analyze ; flutter test' -ForegroundColor Green

