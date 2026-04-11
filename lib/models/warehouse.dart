enum WarehouseStatus {
  online,
  limited,
  maintenance,
}

WarehouseStatus warehouseStatusFromApi(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'online':
      return WarehouseStatus.online;
    case 'limited':
      return WarehouseStatus.limited;
    case 'maintenance':
      return WarehouseStatus.maintenance;
    default:
      return WarehouseStatus.online;
  }
}

extension WarehouseStatusLabel on WarehouseStatus {
  String get labelKey {
    switch (this) {
      case WarehouseStatus.online:
        return 'statusOnline';
      case WarehouseStatus.limited:
        return 'statusLimited';
      case WarehouseStatus.maintenance:
        return 'statusMaintenance';
    }
  }

  String get apiValue {
    switch (this) {
      case WarehouseStatus.online:
        return 'online';
      case WarehouseStatus.limited:
        return 'limited';
      case WarehouseStatus.maintenance:
        return 'maintenance';
    }
  }
}

class Warehouse {
  const Warehouse({
    required this.id,
    required this.name,
    required this.location,
    required this.zoneCount,
    required this.status,
    required this.description,
    required this.totalStorageSlots,
    required this.occupiedStorageSlots,
    required this.articleCount,
    required this.abcAnalysis,
    required this.inboundPerDay,
    required this.throughputPerDay,
    required this.pickRatePerHour,
    required this.zones,
    this.layoutSpec,
    this.generatedModel,
  });

  final String id;
  final String name;
  final String location;
  final int zoneCount;
  final WarehouseStatus status;
  final String description;
  final int totalStorageSlots;
  final int occupiedStorageSlots;
  final int articleCount;
  final AbcAnalysis abcAnalysis;
  final int inboundPerDay;
  final int throughputPerDay;
  final int pickRatePerHour;
  final List<WarehouseZone> zones;
  final WarehouseLayoutSpec? layoutSpec;
  final WarehouseModelData? generatedModel;

  int get freeStorageSlots =>
      (totalStorageSlots - occupiedStorageSlots).clamp(0, totalStorageSlots).toInt();

  double get utilizationRatio {
    if (totalStorageSlots <= 0) {
      return 0;
    }
    return (occupiedStorageSlots / totalStorageSlots).clamp(0, 1).toDouble();
  }

  int get utilizationPercent => (utilizationRatio * 100).round();

  Warehouse copyWith({
    String? id,
    String? name,
    String? location,
    int? zoneCount,
    WarehouseStatus? status,
    String? description,
    int? totalStorageSlots,
    int? occupiedStorageSlots,
    int? articleCount,
    AbcAnalysis? abcAnalysis,
    int? inboundPerDay,
    int? throughputPerDay,
    int? pickRatePerHour,
    List<WarehouseZone>? zones,
    WarehouseLayoutSpec? layoutSpec,
    WarehouseModelData? generatedModel,
  }) {
    return Warehouse(
      id: id ?? this.id,
      name: name ?? this.name,
      location: location ?? this.location,
      zoneCount: zoneCount ?? this.zoneCount,
      status: status ?? this.status,
      description: description ?? this.description,
      totalStorageSlots: totalStorageSlots ?? this.totalStorageSlots,
      occupiedStorageSlots: occupiedStorageSlots ?? this.occupiedStorageSlots,
      articleCount: articleCount ?? this.articleCount,
      abcAnalysis: abcAnalysis ?? this.abcAnalysis,
      inboundPerDay: inboundPerDay ?? this.inboundPerDay,
      throughputPerDay: throughputPerDay ?? this.throughputPerDay,
      pickRatePerHour: pickRatePerHour ?? this.pickRatePerHour,
      zones: zones ?? this.zones,
      layoutSpec: layoutSpec ?? this.layoutSpec,
      generatedModel: generatedModel ?? this.generatedModel,
    );
  }
}

class WarehouseLayoutSpec {
  const WarehouseLayoutSpec({
    required this.lengthM,
    required this.widthM,
    required this.heightM,
    required this.rackRowCount,
    required this.rackLengthM,
    required this.rackWidthM,
    required this.rackLevels,
    required this.aisleWidthM,
    required this.zoneNames,
  });

  final double lengthM;
  final double widthM;
  final double heightM;
  final int rackRowCount;
  final double rackLengthM;
  final double rackWidthM;
  final int rackLevels;
  final double aisleWidthM;
  final List<String> zoneNames;
}

class WarehouseModelData {
  const WarehouseModelData({
    required this.generatedAt,
    required this.warehouseLengthM,
    required this.warehouseWidthM,
    required this.warehouseHeightM,
    required this.shelfRows,
    required this.shelfColumns,
    required this.shelfLevels,
    required this.zones,
  });

  final DateTime generatedAt;
  final double warehouseLengthM;
  final double warehouseWidthM;
  final double warehouseHeightM;
  final int shelfRows;
  final int shelfColumns;
  final int shelfLevels;
  final List<WarehouseModelZone> zones;
}

class WarehouseModelZone {
  const WarehouseModelZone({
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.utilization,
    this.pickRate,
    this.congestion,
    this.abcA,
  });

  final String name;
  final double x;
  final double y;
  final double width;
  final double height;
  final double? utilization;
  final double? pickRate;
  final double? congestion;
  final double? abcA;
}

class AbcAnalysis {
  const AbcAnalysis({
    required this.aCount,
    required this.bCount,
    required this.cCount,
  });

  final int aCount;
  final int bCount;
  final int cCount;

  int get total => aCount + bCount + cCount;

  double get aRatio => total == 0 ? 0 : aCount / total;
  double get bRatio => total == 0 ? 0 : bCount / total;
  double get cRatio => total == 0 ? 0 : cCount / total;
}

class WarehouseZone {
  const WarehouseZone({
    required this.id,
    required this.name,
    required this.totalStorageSlots,
    required this.occupiedStorageSlots,
    required this.articleCount,
    required this.abcAnalysis,
    required this.inboundPerDay,
    required this.throughputPerDay,
    required this.pickRatePerHour,
  });

  final String id;
  final String name;
  final int totalStorageSlots;
  final int occupiedStorageSlots;
  final int articleCount;
  final AbcAnalysis abcAnalysis;
  final int inboundPerDay;
  final int throughputPerDay;
  final int pickRatePerHour;

  int get freeStorageSlots =>
      (totalStorageSlots - occupiedStorageSlots).clamp(0, totalStorageSlots).toInt();

  double get utilizationRatio {
    if (totalStorageSlots <= 0) {
      return 0;
    }
    return (occupiedStorageSlots / totalStorageSlots).clamp(0, 1).toDouble();
  }

  int get utilizationPercent => (utilizationRatio * 100).round();
}

class WarehouseStorageLocation {
  const WarehouseStorageLocation({
    required this.placeId,
    required this.area,
    required this.rackNumber,
    required this.levelNumber,
    required this.slotNumber,
    required this.abcClass,
    required this.status,
  });

  final String placeId;
  final String area;
  final int rackNumber;
  final int levelNumber;
  final int slotNumber;
  final String abcClass;
  final String status;

  String get displayCode =>
      'R${rackNumber.toString().padLeft(2, "0")}-'
      'E${levelNumber.toString().padLeft(2, "0")}-'
      'F${slotNumber.toString().padLeft(3, "0")}';
}
