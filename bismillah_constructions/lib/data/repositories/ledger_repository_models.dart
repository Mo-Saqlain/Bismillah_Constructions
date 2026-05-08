// Result classes returned by [LedgerRepository] methods. Kept as a
// `part of` so callers continue to import the single
// `ledger_repository.dart` file and get every related type in one go.
part of 'ledger_repository.dart';

class MonthlyCashFlow {
  final DateTime month;
  final Map<String, double> perAccount;
  const MonthlyCashFlow({required this.month, required this.perAccount});
  double get total => perAccount.values.fold(0, (a, b) => a + b);
}

/// Result of [LedgerRepository.incomeFigures]. Single source of truth for
/// every "what's our P&L?" surface (Income Statement, dashboard Net Profit).
class IncomeFigures {
  /// Recognized contract revenue from With-Material projects, computed via
  /// cost-recovery PoC for active jobs and full contract recognition for
  /// closed jobs.
  final double wmRevenue;
  final double serviceFees;
  final double matCosts;
  final double labCosts;
  final double personalDraw;

  /// Customer money received but not yet earned — sits as a liability.
  final double lrDeposit;
  final double wmDeposit;

  /// Sum of (costs - budget) across every project where costs exceeded
  /// budget. Recognized as an immediate cost line per FASB/IFRS loss
  /// provision rules.
  final double lossProvision;

  /// Projects whose cost-to-date is ≥ 80% of budget. Sorted with already-
  /// over-budget jobs first, then by % consumed descending.
  final List<ProjectAtRisk> projectsAtRisk;

  const IncomeFigures({
    required this.wmRevenue,
    required this.serviceFees,
    required this.matCosts,
    required this.labCosts,
    required this.personalDraw,
    required this.lrDeposit,
    required this.wmDeposit,
    required this.lossProvision,
    required this.projectsAtRisk,
  });

  double get totalIncome => wmRevenue + serviceFees;
  double get totalCosts => matCosts + labCosts + personalDraw + lossProvision;
  double get netProfit => totalIncome - totalCosts;
  double get totalDeposit => lrDeposit + wmDeposit;
}

/// One project's risk snapshot for the dashboard's "Projects at Risk" panel.
class ProjectAtRisk {
  final String projectId;
  final String projectName;
  final double budget;
  final double costsToDate;

  /// 0..100+ — values above 100 mean already over budget.
  final double pctConsumed;
  final bool isOverBudget;

  const ProjectAtRisk({
    required this.projectId,
    required this.projectName,
    required this.budget,
    required this.costsToDate,
    required this.pctConsumed,
    required this.isOverBudget,
  });
}

/// Indirect-method cash flow summary across every cash-like account.
///
/// All `*flow` and `*Outflow` numbers are stored as positive values;
/// the sign is implicit from the field name. `netChange` walks
/// opening cash → closing cash through the bucketed activity totals.
class CashFlowSummary {
  /// Cash position at the moment the period opened (sum of all cash-like
  /// account balances right before `from`). Zero when no `from` is set.
  final double openingCash;
  final double operatingInflow;
  final double operatingOutflow;
  final double financingOutflow;

  /// Catch-all for cash legs whose sibling didn't land in any of the
  /// canonical buckets — e.g. legacy data, manual journal corrections.
  final double otherNet;

  const CashFlowSummary({
    required this.openingCash,
    required this.operatingInflow,
    required this.operatingOutflow,
    required this.financingOutflow,
    required this.otherNet,
  });

  static const empty = CashFlowSummary(
    openingCash: 0,
    operatingInflow: 0,
    operatingOutflow: 0,
    financingOutflow: 0,
    otherNet: 0,
  );

  double get netOperating => operatingInflow - operatingOutflow;
  double get netFinancing => -financingOutflow;
  double get netChange => netOperating + netFinancing + otherNet;
  double get closingCash => openingCash + netChange;
}

class WageRegisterLine {
  final String supplierId;
  final int paymentCount;
  final double totalPaid;
  final DateTime lastPaidAt;
  const WageRegisterLine({
    required this.supplierId,
    required this.paymentCount,
    required this.totalPaid,
    required this.lastPaidAt,
  });
}

class ProjectBva {
  /// Keyed by the human-readable material label (e.g. "Cement"). User-defined
  /// types appear here verbatim; legacy enum-name rows are normalized via
  /// [resolveMaterialLabel].
  final Map<String, double> materialByType;
  final double otherMaterial;
  final double labour;
  const ProjectBva({
    required this.materialByType,
    required this.otherMaterial,
    required this.labour,
  });
  double get totalMaterial =>
      materialByType.values.fold<double>(0, (a, b) => a + b) + otherMaterial;
  double get totalSpend => totalMaterial + labour;
}

class PricePoint {
  final DateTime date;
  final double rate;
  const PricePoint({required this.date, required this.rate});
}

class BurnPoint {
  final DateTime date;
  final double cumulativeSpend;
  const BurnPoint({required this.date, required this.cumulativeSpend});
}

class DailySpend {
  final DateTime date;
  final double amount;
  const DailySpend({required this.date, required this.amount});
}

class SupplierSpend {
  final String supplierId;
  final double total;
  const SupplierSpend({required this.supplierId, required this.total});
}

class _OpenInvoice {
  _OpenInvoice({required this.date, required this.remaining});
  final DateTime date;
  double remaining;
}

class AgingLine {
  final String partyId;
  final double bucket0_30;
  final double bucket31_60;
  final double bucket61_90;
  final double bucket90Plus;
  const AgingLine({
    required this.partyId,
    required this.bucket0_30,
    required this.bucket31_60,
    required this.bucket61_90,
    required this.bucket90Plus,
  });
  double get total => bucket0_30 + bucket31_60 + bucket61_90 + bucket90Plus;
}

class AgingReport {
  final DateTime asOf;
  final List<AgingLine> lines;
  const AgingReport({required this.asOf, required this.lines});

  double get total0_30 => lines.fold(0, (s, l) => s + l.bucket0_30);
  double get total31_60 => lines.fold(0, (s, l) => s + l.bucket31_60);
  double get total61_90 => lines.fold(0, (s, l) => s + l.bucket61_90);
  double get total90Plus => lines.fold(0, (s, l) => s + l.bucket90Plus);
  double get grandTotal => total0_30 + total31_60 + total61_90 + total90Plus;
}

/// Settlement snapshot returned by [LedgerRepository.labourRateCloseSummary].
///
/// Sign convention on [netToSettle]:
///   * Positive → contractor is holding the customer's surplus → refund it.
///   * Negative → spending overran customer's deposits → customer owes us
///     this amount (deficit + service fee, packed into one number).
class LabourRateClose {
  final double customerPaid;
  final double totalSpent;
  final double feePercent;
  final double serviceFee;
  final double netToSettle;

  const LabourRateClose({
    required this.customerPaid,
    required this.totalSpent,
    required this.feePercent,
    required this.serviceFee,
    required this.netToSettle,
  });

  /// Amount the contractor has to refund (0 when the customer underpaid).
  double get refundToCustomer => netToSettle > 0 ? netToSettle : 0;

  /// Amount the customer still owes (0 when overpaid). Already includes
  /// the service fee in the deficit case.
  double get customerOwesUs => netToSettle < 0 ? -netToSettle : 0;
}

class ProjectReconciliation {
  /// Total received from the project (credits to PROJECT_REV for this project).
  final double projectInflow;

  /// Sum of debits to SUPPLIER_PAY for this project.
  final double supplierPaid;

  /// Outstanding payables (credits − debits) on SUPPLIER_PAY for this project.
  final double supplierPayables;

  const ProjectReconciliation({
    required this.projectInflow,
    required this.supplierPaid,
    required this.supplierPayables,
  });

  /// New rule (post-customer-removal): reconciled when no payables remain.
  /// The cash received minus costs incurred is the project's savings/profit
  /// and does not need to balance to zero.
  bool get isBalanced => supplierPayables.abs() < 0.01;

  /// Net cash position from project = inflow − supplier obligations (paid + open).
  double get savings => projectInflow - (supplierPaid + supplierPayables);
}
