class ReplenishmentCandidate {
  const ReplenishmentCandidate({
    required this.placeId,
    required this.rackNumber,
    required this.levelNumber,
    required this.slotNumber,
    required this.picks,
    required this.daysEmpty,
    required this.leerDatum,
    required this.reason,
  });

  final String placeId;
  final int rackNumber;
  final int levelNumber;
  final int slotNumber;
  final int picks;
  final int daysEmpty;
  final String leerDatum;
  final String reason;

  String get displayCode {
    final r = rackNumber.toString().padLeft(2, '0');
    final e = levelNumber.toString();
    final f = slotNumber.toString().padLeft(2, '0');
    return 'R$r-E$e-F$f';
  }
}

class ReplenishmentCandidateSummary {
  const ReplenishmentCandidateSummary({
    required this.urgent,
    required this.overdue,
    required this.medium,
    required this.pickThreshold,
    required this.mediumPickThreshold,
    required this.overdueDays,
    required this.pickLevel,
    required this.urgentPlaces,
    required this.overduePlaces,
    required this.mediumPlaces,
  });

  /// Aktiver Pickplatz leer (Picks>=pickThreshold, Ebene<=pickLevel, nicht gesperrt).
  final int urgent;

  /// Wie urgent, aber LEER_DATUM aelter als overdueDays.
  final int overdue;

  /// Mittlere Frequenz: mediumPickThreshold..pickThreshold-1.
  final int medium;

  final int pickThreshold;
  final int mediumPickThreshold;
  final int overdueDays;
  final int pickLevel;

  final List<ReplenishmentCandidate> urgentPlaces;
  final List<ReplenishmentCandidate> overduePlaces;
  final List<ReplenishmentCandidate> mediumPlaces;

  static const ReplenishmentCandidateSummary empty =
      ReplenishmentCandidateSummary(
    urgent: 0,
    overdue: 0,
    medium: 0,
    pickThreshold: 50,
    mediumPickThreshold: 20,
    overdueDays: 14,
    pickLevel: 2,
    urgentPlaces: <ReplenishmentCandidate>[],
    overduePlaces: <ReplenishmentCandidate>[],
    mediumPlaces: <ReplenishmentCandidate>[],
  );

  bool get isEmpty => urgent == 0 && overdue == 0 && medium == 0;
  int get total => urgent + medium;
}
