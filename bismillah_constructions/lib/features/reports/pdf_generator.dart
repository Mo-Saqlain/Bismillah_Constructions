import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/formatters.dart';
import '../../data/models/journal_entry.dart';

class IncomeStatementData {
  final String? projectName;
  final double revenue;
  final double materialCosts;
  final double labourCosts;
  final DateTime generatedAt;
  IncomeStatementData({
    this.projectName,
    required this.revenue,
    required this.materialCosts,
    required this.labourCosts,
    required this.generatedAt,
  });
  double get net => revenue - (materialCosts + labourCosts);
}

class BalanceSheetData {
  final double cash;
  final double supervisorFloat;
  /// (name, balance) pairs for each user-defined bank/wallet.
  final List<(String, double)> bankRows;
  final double counterReceivables;
  final double payables;
  final double counterPayables;
  final double equity;
  final DateTime generatedAt;
  BalanceSheetData({
    required this.cash,
    required this.supervisorFloat,
    required this.bankRows,
    required this.counterReceivables,
    required this.payables,
    required this.counterPayables,
    required this.equity,
    required this.generatedAt,
  });
  double get totalBanks =>
      bankRows.fold<double>(0, (a, r) => a + r.$2);
  double get assets =>
      cash + supervisorFloat + totalBanks + counterReceivables;
  double get liabPlusEquity => payables + counterPayables + equity;
  bool get balanced => (assets - liabPlusEquity).abs() < 0.01;
}

class SupplierLedgerData {
  final String supplierName;
  final List<JournalEntry> rows;
  final DateTime generatedAt;
  SupplierLedgerData({
    required this.supplierName,
    required this.rows,
    required this.generatedAt,
  });
}

class BankLedgerData {
  final String bankName;
  final List<JournalEntry> rows;
  final DateTime generatedAt;
  BankLedgerData({
    required this.bankName,
    required this.rows,
    required this.generatedAt,
  });
}

class ProjectLedgerData {
  final String projectName;
  final List<JournalEntry> rows;
  final DateTime generatedAt;
  ProjectLedgerData({
    required this.projectName,
    required this.rows,
    required this.generatedAt,
  });
}

class PdfGenerator {
  static Future<void> previewIncomeStatement(IncomeStatementData d) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat f) => _buildIncomeStatement(d),
      name: 'Income Statement',
    );
  }

  static Future<void> previewBalanceSheet(BalanceSheetData d) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat f) => _buildBalanceSheet(d),
      name: 'Balance Sheet',
    );
  }

  static Future<void> previewSupplierLedger(SupplierLedgerData d) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat f) => _buildSupplierLedger(d),
      name: 'Supplier Ledger — ${d.supplierName}',
    );
  }

  static Future<void> previewBankLedger(BankLedgerData d) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat f) => _buildBankLedger(d),
      name: 'Bank Ledger — ${d.bankName}',
    );
  }

  static Future<void> previewProjectLedger(ProjectLedgerData d) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat f) => _buildProjectLedger(d),
      name: 'Project Ledger — ${d.projectName}',
    );
  }

  // ---- Builders ----

  static pw.Widget _header(String title, String subtitle) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Bismillah',
              style: pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.Text(subtitle,
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.Divider(),
        ],
      );

  static pw.Widget _line(String label, double v, {bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text(fmtMoney(v),
                style: pw.TextStyle(
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );

  static Future<Uint8List> _buildIncomeStatement(
      IncomeStatementData d) async {
    final doc = pw.Document();
    doc.addPage(pw.Page(
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header(
              'Income Statement',
              'Project: ${d.projectName ?? "All Projects"}  ·  '
                  'As of ${fmtDateTime(d.generatedAt)}'),
          pw.SizedBox(height: 12),
          _line('Project Revenue', d.revenue, bold: true),
          pw.SizedBox(height: 8),
          pw.Text('Direct Costs',
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold)),
          _line('  Material Costs', d.materialCosts),
          _line('  Labour Costs', d.labourCosts),
          _line('  Total Costs', d.materialCosts + d.labourCosts, bold: true),
          pw.Divider(),
          _line('Net Profit / (Loss)', d.net, bold: true),
        ],
      ),
    ));
    return doc.save();
  }

  static Future<Uint8List> _buildBalanceSheet(BalanceSheetData d) async {
    final doc = pw.Document();
    doc.addPage(pw.Page(
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header('Balance Sheet',
              'As of ${fmtDateTime(d.generatedAt)}'),
          pw.SizedBox(height: 12),
          pw.Text('Assets',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          _line('  Cash', d.cash),
          _line('  Supervisor Float', d.supervisorFloat),
          for (final r in d.bankRows) _line('  ${r.$1}', r.$2),
          if (d.counterReceivables > 0)
            _line('  Counter Receivables', d.counterReceivables),
          _line('Total Assets', d.assets, bold: true),
          pw.SizedBox(height: 12),
          pw.Text('Liabilities & Equity',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          _line('  Supplier Payables', d.payables),
          if (d.counterPayables > 0)
            _line('  Counter Payables', d.counterPayables),
          _line("  Owner's Equity", d.equity),
          _line('Total Liabilities + Equity', d.liabPlusEquity, bold: true),
          pw.SizedBox(height: 12),
          if (!d.balanced)
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.red50,
                border: pw.Border.all(color: PdfColors.red),
              ),
              child: pw.Text(
                'WARNING: Assets do not equal Liabilities + Equity. '
                'Difference: ${fmtMoney(d.assets - d.liabPlusEquity)}',
                style: pw.TextStyle(
                    color: PdfColors.red, fontWeight: pw.FontWeight.bold),
              ),
            ),
        ],
      ),
    ));
    return doc.save();
  }

  static Future<Uint8List> _buildBankLedger(BankLedgerData d) async {
    final doc = pw.Document();
    double running = 0;
    final tableRows = <List<String>>[
      ['Date', 'Memo', 'Debit (in)', 'Credit (out)', 'Balance'],
    ];
    for (final r in d.rows) {
      running += r.debit - r.credit;
      tableRows.add([
        fmtDate(r.createdAt),
        r.description ?? '—',
        r.debit > 0 ? fmtMoney(r.debit) : '',
        r.credit > 0 ? fmtMoney(r.credit) : '',
        fmtMoney(running),
      ]);
    }
    doc.addPage(pw.MultiPage(
      build: (ctx) => [
        _header('Bank / Wallet Ledger',
            '${d.bankName}  ·  Generated ${fmtDateTime(d.generatedAt)}'),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration:
              const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
          },
          data: tableRows,
        ),
        pw.SizedBox(height: 16),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Net Balance: ${fmtMoney(running)}',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ),
      ],
    ));
    return doc.save();
  }

  static Future<Uint8List> _buildProjectLedger(ProjectLedgerData d) async {
    final doc = pw.Document();
    double running = 0;
    final tableRows = <List<String>>[
      ['Date', 'Memo', 'Debit', 'Credit', 'Running'],
    ];
    final byTxn = <String, List<JournalEntry>>{};
    for (final r in d.rows) {
      (byTxn[r.transactionId] ??= []).add(r);
    }
    for (final pair in byTxn.values) {
      if (pair.length != 2) continue;
      final dr = pair.firstWhere((e) => e.debit > 0);
      running += dr.debit - dr.credit;
      tableRows.add([
        fmtDate(dr.createdAt),
        dr.description ?? '—',
        dr.debit > 0 ? fmtMoney(dr.debit) : '',
        dr.credit > 0 ? fmtMoney(dr.credit) : '',
        fmtMoney(running),
      ]);
    }
    doc.addPage(pw.MultiPage(
      build: (ctx) => [
        _header('Project Ledger',
            '${d.projectName}  ·  Generated ${fmtDateTime(d.generatedAt)}'),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration:
              const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
          },
          data: tableRows,
        ),
      ],
    ));
    return doc.save();
  }

  static Future<Uint8List> _buildSupplierLedger(
      SupplierLedgerData d) async {
    final doc = pw.Document();
    double running = 0;
    final tableRows = <List<String>>[
      ['Date', 'Description', 'Debit', 'Credit', 'Balance'],
    ];
    for (final r in d.rows) {
      // For supplier payables: credits increase, debits decrease.
      running += r.credit - r.debit;
      tableRows.add([
        fmtDate(r.createdAt),
        r.description ?? '—',
        r.debit > 0 ? fmtMoney(r.debit) : '',
        r.credit > 0 ? fmtMoney(r.credit) : '',
        fmtMoney(running),
      ]);
    }

    doc.addPage(pw.MultiPage(
      build: (ctx) => [
        _header('Supplier Ledger',
            '${d.supplierName}  ·  Generated ${fmtDateTime(d.generatedAt)}'),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration:
              const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
          },
          data: tableRows,
        ),
        pw.SizedBox(height: 16),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Net Outstanding: ${fmtMoney(running)}',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ),
      ],
    ));
    return doc.save();
  }
}
