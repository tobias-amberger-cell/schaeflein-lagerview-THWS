import 'database_service_base.dart';

DatabaseService createDatabaseService() => _WebDatabaseService();

class _WebDatabaseService implements DatabaseService {
  @override
  Future<DatabaseBootstrapResult> ensureDatabaseReady() async {
    // Im Browser wird der Datenzugriff weiterhin ueber API abgewickelt.
    return const DatabaseBootstrapResult(
      errorMessage:
          'Lokaler SQLite-Download ist im Web deaktiviert. Nutze API-Datenquelle.',
    );
  }
}

