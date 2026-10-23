import 'logic.dart';
import 'pay.dart' show round2;

/// Custody (عهدة) maths, the same as the web app (src/custody.jsx and src/invoices.jsx): a person is given cash
/// ('give'), brings back invoices/expenses ('expense') and may return cash ('return'). 'open' is the balance carried
/// into a new year by the year-end close (signed). Only the signed-in user's own records are ever loaded —
/// see my_custody() in docs/API.md.

const defaultVat = 15.0;

class InvTotals {
  final double sub, disc, taxable, vat, rate, total;
  const InvTotals(this.sub, this.disc, this.taxable, this.vat, this.rate, this.total);
}

/// Items → subtotal → discount → VAT → total, always from the lines (an empty VAT rate means the default 15%).
InvTotals invTotals(Json inv) {
  final items = (inv['items'] as List?) ?? const [];
  final sub = items.fold<double>(0, (a, r) => a + toNum((r as Map)['qty']) * toNum(r['rate']));
  final disc = toNum(inv['discount']) > sub ? sub : toNum(inv['discount']);
  final taxable = sub - disc;
  final r = str(inv['vatRate']).trim();
  final rate = r.isEmpty ? defaultVat : toNum(r);
  final vat = taxable * rate / 100;
  return InvTotals(sub, disc, taxable, vat, rate, taxable + vat);
}

double amountOf(Json t) => t['type'] == 'expense' ? invTotals(t).total : toNum(t['amount']);

/// An invoice added by the user waits for the accounts manager ('pending') and may be 'rejected'; only approved ones
/// count in balances. Invoices without a status (older records, or entered by the accounts manager) are approved.
String statusOf(Json t) => t['type'] == 'expense' && str(t['status']).isNotEmpty ? str(t['status']) : 'approved';
bool counts(Json t) => statusOf(t) == 'approved';

/// Effect on what the person is holding: cash given and an opening balance add, expenses and returns subtract.
double deltaOf(Json t) => !counts(t) ? 0 : (t['type'] == 'expense' || t['type'] == 'return' ? -amountOf(t) : amountOf(t));

class CustodyTotals {
  final double opening, given, spent, spentProject, spentOutside, returned;
  const CustodyTotals(this.opening, this.given, this.spent, this.spentProject, this.spentOutside, this.returned);
  double get balance => opening + given - spent - returned;
}

CustodyTotals custodyTotals(Iterable<Json> txs) {
  double opening = 0, given = 0, spent = 0, spentProject = 0, spentOutside = 0, returned = 0;
  for (final x in txs) {
    if (!counts(x)) continue;
    final a = amountOf(x);
    switch (str(x['type'])) {
      case 'open':
        opening += a;
      case 'give':
        given += a;
      case 'return':
        returned += a;
      default:
        spent += a;
        if (str(x['projectId']).isNotEmpty) {
          spentProject += a;
        } else {
          spentOutside += a;
        }
    }
  }
  return CustodyTotals(opening, given, spent, spentProject, spentOutside, returned);
}

/// The transactions in time order, each with the running balance after it.
List<(Json, double)> custodyLedger(Iterable<Json> txs) {
  final list = [...txs]..sort((a, b) {
      final c = str(a['date']).compareTo(str(b['date']));
      return c != 0 ? c : str(a['at']).compareTo(str(b['at']));
    });
  var bal = 0.0;
  return [for (final t in list) (t, round2(bal += deltaOf(t)))];
}
