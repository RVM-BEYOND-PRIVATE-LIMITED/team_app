/// The one way an amount is shown in the apps (team_app #55, student_app #1).
///
/// The server sends money as whole paise and decides every amount; the app
/// only displays it. The text is built from the integer's digits, never with
/// division or doubles, so no amount is ever rounded on the phone.
abstract final class RvmMoney {
  /// The rupee sign that leads every amount.
  static const symbol = '₹';

  /// Rupee text for [paise], with Indian digit grouping: the last three
  /// rupee digits, then pairs (₹12,34,567). The paise appear as `.NN` only
  /// when they are not zero, and a negative amount reads `-₹…`.
  ///
  /// `fromPaise(123456789)` is `₹12,34,567.89`; `fromPaise(100000)` is
  /// `₹1,000`; `fromPaise(-1)` is `-₹0.01`.
  static String fromPaise(int paise) {
    final text = paise.toString();
    final negative = text.startsWith('-');
    // Digits only, so the smallest int (whose negation does not fit) works too.
    final digits = (negative ? text.substring(1) : text).padLeft(3, '0');
    final rupees = digits.substring(0, digits.length - 2);
    final fraction = digits.substring(digits.length - 2);
    return '${negative ? '-' : ''}$symbol${_grouped(rupees)}'
        '${fraction == '00' ? '' : '.$fraction'}';
  }

  /// The rupee digits in Indian groups: the last three, then pairs.
  static String _grouped(String digits) {
    if (digits.length <= 3) return digits;
    final head = digits.substring(0, digits.length - 3);
    final tail = digits.substring(digits.length - 3);
    final pairs = <String>[];
    for (var end = head.length; end > 0; end -= 2) {
      pairs.insert(0, head.substring(end < 2 ? 0 : end - 2, end));
    }
    return '${pairs.join(',')},$tail';
  }
}
