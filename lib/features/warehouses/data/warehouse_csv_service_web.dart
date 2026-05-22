import '../../../models/warehouse.dart';
import '../../../models/warehouse_operations_profile.dart';
import '../../../models/warehouse_trend.dart';

// Web kann die lokale warehouse.db nicht direkt lesen.
// DB-only Modus: auf Web werden bewusst keine Daten als Fallback geladen.
class WarehouseCsvService {
  WarehouseCsvService({this.dataDirectory});

  final String? dataDirectory;

  Future<List<Warehouse>> loadWarehousesFromDisk() async {
    throw UnsupportedError(
      'DB-only Modus ist im Web nicht direkt möglich. Nutze Desktop oder eine API.',
    );
  }

  Future<Map<String, WarehouseOperationsProfile>>
      loadOperationsProfilesFromDisk() async {
    return <String, WarehouseOperationsProfile>{};
  }

  Future<List<WarehouseStorageLocation>> loadStorageLocationsFromDisk({
    int limit = 24,
    String? warehouseId,
  }) async {
    return <WarehouseStorageLocation>[];
  }

  Future<List<WarehouseTrendPoint>> loadThroughputTrendFromDisk({
    int days = 14,
  }) async {
    return <WarehouseTrendPoint>[];
  }

  Future<Map<String, String>> loadExternalModelPathsFromDisk() async {
    return <String, String>{};
  }

  Future<String?> loadActiveDatabasePathFromDisk() async {
    return null;
  }

  Future<List<String>> loadAvailableDatabasePathsFromDisk() async {
    return <String>[];
  }

  Future<Map<String, List<WarehouseAbcArticleSummary>>>
      loadAbcArticlesFromDisk({
    int limit = 5000,
  }) async {
    return <String, List<WarehouseAbcArticleSummary>>{};
  }

  Future<Map<String, List<WarehouseAbcSlotSummary>>> loadAbcSlotsFromDisk({
    int limit = 10000,
  }) async {
    return <String, List<WarehouseAbcSlotSummary>>{};
  }
}
