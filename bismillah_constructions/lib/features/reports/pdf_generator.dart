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
  final double bankHbl;
  final double bankMeezan;
  final double receivables;
  final double payables;
  final double equity;
  final DateTime generatedAt;
  BalanceSheetData({
    required this.cash,
    required this.bankHbl,
    required this.bankMeezan,
    required this.receivables,
    required this.payables,
    required this.equity,
    required this.generatedAt,
  });
  double get assets => cash + bankHbl + bankMeezan + receivables;
  double get liabPlusEquity => payables + equity;
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
          _line('  Bank — HBL', d.bankHbl),
          _line('  Bank — Meezan', d.bankMeezan),
          _line('  Client Receivables', d.receivables),
          _line('Total Assets', d.assets, bold: true),
          pw.SizedBox(height: 12),
          pw.Text('Liabilities & Equity',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          _line('  Supplier Payables', d.payables),
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
