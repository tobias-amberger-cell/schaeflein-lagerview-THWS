import 'database_service_base.dart';

DatabaseService createDatabaseService() => _UnsupportedDatabaseService();

class _UnsupportedDatabaseService implements DatabaseService {
  @override
  Future<DatabaseBootstrapResult> ensureDatabaseReady() async {
    return const DatabaseBootstrapResult(
      errorMessage: 'Lokaler SQLite-Download ist auf dieser Plattform nicht verfuegbar.',
    );
  }
}

