/// The exact vocabulary the Printiverse financial workbook expects.
///
/// Every string here must match tab `01_Lists` of
/// `Printiverse_Financial_Report_Template.xlsx` character for character,
/// because the expense export is pasted straight into tab
/// `3_Expense_Ledger` and the workbook's checks reject unknown values.
/// If a list is changed in the workbook, change it here too.
class ExpenseOptions {
  ExpenseOptions._();

  // --- Cost Types (01_Lists column D) ---------------------------------
  static const String cogs = 'COGS';
  static const String opex = 'OpEx';
  static const String capex = 'CapEx';
  static const String taxRemittance = 'Tax Remittance';
  static const String drawings = 'Drawings';
  static const String loanRepayment = 'Loan Repayment';

  static const List<String> costTypes = [
    cogs,
    opex,
    capex,
    taxRemittance,
    drawings,
    loanRepayment,
  ];

  // --- Categories, keyed by Cost Type (01_Lists columns E to J) -------
  static const Map<String, List<String>> categoriesByCostType = {
    cogs: [
      'Substrates & Media',
      'Inks, Toners & Plates',
      'Finishing Consumables',
      'Outsourced Print / Finishing',
    ],
    opex: [
      'Power & Generator Fuel',
      'Machine Maintenance & Parts',
      'Staff Salaries & Wages',
      'Logistics & Dispatch',
      'Rent & Shop Levies',
      'Internet, Software & Admin',
      'Marketing & Advertising',
      'Professional & Filing Fees',
      'Bank & POS Charges',
      'Pension, PAYE & Staff Welfare',
      'Insurance',
      'Miscellaneous / Other',
    ],
    capex: [
      'Printing Machines & Equipment',
      'Computers & Office Equipment',
      'Generator & Power Equipment',
      'Furniture & Fittings',
      'Vehicles',
    ],
    taxRemittance: [
      'VAT Remittance',
      'WHT Remittance',
      'Income Tax & Levies',
    ],
    drawings: [
      'Owner Drawings / Dividends',
    ],
    loanRepayment: [
      'Loan Principal Repayment',
    ],
  };

  // --- Payment Accounts (01_Lists column K) ---------------------------
  static const List<String> paymentAccounts = [
    'Business Bank',
    'Petty Cash',
    'POS / Till Cash',
    'Mobile Money',
  ];

  // --- Receipt / Audit Status (01_Lists column L) ---------------------
  static const List<String> receiptStatuses = [
    'Attached (Drive)',
    'Physical Receipt',
    'Payroll Schedule',
    'No Receipt (Missing)',
  ];

  // --- Rules ----------------------------------------------------------

  /// Categories allowed for [costType]; empty if the cost type is unknown.
  static List<String> categoriesFor(String costType) =>
      categoriesByCostType[costType] ?? const [];

  /// Tax Remittance, Drawings and Loan Repayment rows must carry no Input
  /// VAT and no WHT (workbook check: tab 10, row 16).
  static bool allowsVatAndWht(String costType) =>
      costType != taxRemittance &&
      costType != drawings &&
      costType != loanRepayment;

  /// CapEx rows need a serial number or asset tag in the Notes column.
  static bool requiresAssetTag(String costType) => costType == capex;

  /// True if [category] is a valid category for [costType].
  static bool isValidPair(String costType, String category) =>
      categoriesFor(costType).contains(category);
}
