/// A public promotional offer (GET /public/active-offer). The endpoint returns
/// `{ offer: null | {...} }`, so this is only built when an offer is live.
class Offer {
  const Offer({
    required this.id,
    required this.name,
    this.message,
    this.pricePaise,
    this.validTo,
  });

  final String id;
  final String name;
  final String? message;
  final int? pricePaise;
  final DateTime? validTo;

  /// Price in rupees (paise/100), for display.
  double? get priceRupees => pricePaise == null ? null : pricePaise! / 100;
}
