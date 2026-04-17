class WarehouseTrendPoint {
  const WarehouseTrendPoint({
    required this.date,
    required this.value,
  });

  final DateTime date;
  final int value;

  String get shortLabel =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
}
