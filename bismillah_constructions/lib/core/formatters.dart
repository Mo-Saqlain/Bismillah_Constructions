import 'package:intl/intl.dart';

final _money = NumberFormat.currency(
  locale: 'en_PK',
  symbol: 'Rs ',
  decimalDigits: 0,
);

String fmtMoney(num? v) {
  if (v == null) return '—';
  return _money.format(v);
}

String fmtSignedMoney(num v) {
  final s = fmtMoney(v.abs());
  return v < 0 ? '-$s' : s;
}

final _date = DateFormat('dd MMM yyyy');
final _dateTime = DateFormat('dd MMM yyyy · hh:mm a');

String fmtDate(DateTime d) => _date.format(d.toLocal());
String fmtDateTime(DateTime d) => _dateTime.format(d.toLocal());
