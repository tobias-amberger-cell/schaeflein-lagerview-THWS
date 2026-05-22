class RelocationCandidate {
  const RelocationCandidate({
    required this.placeId,
    required this.rackNumber,
    required this.levelNumber,
    required this.slotNumber,
    required this.picks,
    required this.abcClass,
    required this.reason,
  });

  final String placeId;
  final int rackNumber;
  final int levelNumber;
  final int slotNumber;
  final int picks;
  final String abcClass;
  final String reason;

  String get displayCode {
    final r = rackNumber.toString().padLeft(2, '0');
    final e = levelNumber.toString();
    final f = slotNumber.toString().padLeft(2, '0');
    return 'R$r-E$e-F$f';
  }
}

class RelocationCandidateSummary {
  const RelocationCandidateSummary({
    required this.unusedA,
    required this.hotC,
    required this.highLevelA,
    required this.highPickThreshold,
    required this.highLevel,
    required this.unusedAPlaces,
    required this.hotCPlaces,
    required this.highLevelAPlaces,
  });

  /// Anzahl A-Plaetze ohne Picks (nicht gesperrt) - Premium-Platz wird verschwendet.
  final int unusedA;

  /// Anzahl C-Plaetze mit Picks >= highPickThreshold - falsche Klasse vergeben.
  final int hotC;

  /// Anzahl aktiver A-Plaetze auf Ebene >= highLevel - sollten runter geholt werden.
  final int highLevelA;

  final int highPickThreshold;
  final int highLevel;

  final List<RelocationCandidate> unusedAPlaces;
  final List<RelocationCandidate> hotCPlaces;
  final List<RelocationCandidate> highLevelAPlaces;

  static const RelocationCandidateSummary empty = RelocationCandidateSummary(
    unusedA: 0,
    hotC: 0,
    highLevelA: 0,
    highPickThreshold: 100,
    highLevel: 4,
    unusedAPlaces: <RelocationCandidate>[],
    hotCPlaces: <RelocationCandidate>[],
    highLevelAPlaces: <RelocationCandidate>[],
  );

  bool get isEmpty => unusedA == 0 && hotC == 0 && highLevelA == 0;
  int get total => unusedA + hotC + highLevelA;
}
