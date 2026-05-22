class OrderVolumePoint {
  const OrderVolumePoint({
    required this.date,
    required this.orders,
    required this.positions,
    required this.quantity,
  });

  final DateTime date;
  final int orders;
  final int positions;
  final int quantity;

  String get shortLabel =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
}
