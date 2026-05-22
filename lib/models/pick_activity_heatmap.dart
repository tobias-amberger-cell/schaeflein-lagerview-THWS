class PickActivityHeatmap {
  const PickActivityHeatmap({
    required this.minDate,
    required this.maxDate,
    required this.maxPicks,
    required this.cells,
  });

  final DateTime? minDate;
  final DateTime? maxDate;
  final int maxPicks;
  final List<PickActivityCell> cells;

  static const PickActivityHeatmap empty = PickActivityHeatmap(
    minDate: null,
    maxDate: null,
    maxPicks: 0,
    cells: <PickActivityCell>[],
  );

  bool get isEmpty => cells.isEmpty;

  /// Liefert die Pick-Anzahl fuer (Wochentag, Stunde) oder 0,
  /// falls keine Zelle vorhanden ist.
  int picksAt(int weekday, int hour) {
    for (final cell in cells) {
      if (cell.weekday == weekday && cell.hour == hour) {
        return cell.picks;
      }
    }
    return 0;
  }
}

class PickActivityCell {
  const PickActivityCell({
    required this.weekday,
    required this.hour,
    required this.picks,
  });

  /// 0 = Sonntag, 1 = Montag, ..., 6 = Samstag (SQLite-strftime('%w')-Konvention).
  final int weekday;

  /// 0..23
  final int hour;

  final int picks;
}
