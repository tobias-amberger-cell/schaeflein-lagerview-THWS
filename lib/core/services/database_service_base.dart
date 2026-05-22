class DatabaseBootstrapResult {
  const DatabaseBootstrapResult({
    this.databasePath,
    this.errorMessage,
  });

  final String? databasePath;
  final String? errorMessage;

  bool get isSuccess =>
      databasePath != null && databasePath!.trim().isNotEmpty;
}

abstract class DatabaseService {
  Future<DatabaseBootstrapResult> ensureDatabaseReady();
}

