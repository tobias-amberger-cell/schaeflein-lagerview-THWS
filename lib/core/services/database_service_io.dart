import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../constants/app_constants.dart';
import 'database_service_base.dart';

DatabaseService createDatabaseService() => _IoDatabaseService();

class _IoDatabaseService implements DatabaseService {
  _IoDatabaseService() : _dio = Dio();

  final Dio _dio;

  @override
  Future<DatabaseBootstrapResult> ensureDatabaseReady() async {
    final dbFile = await _resolveDatabaseFile();
    if (await dbFile.exists()) {
      try {
        _validateReadOnlyDatabase(dbFile.path);
        return DatabaseBootstrapResult(databasePath: dbFile.path);
      } catch (_) {
        // Defekte Datei entfernen und sauber neu laden.
        await dbFile.delete();
      }
    }

    final downloadUrl = AppConstants.warehouseDbDownloadUrl.trim();
    if (!_isValidDownloadUrl(downloadUrl)) {
      return const DatabaseBootstrapResult(
        errorMessage:
            'Kein gueltiger Download-Link fuer warehouse.db konfiguriert.',
      );
    }

    final tempPath = '${dbFile.path}.download';
    final tempFile = File(tempPath);
    try {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      await _dio.download(
        downloadUrl,
        tempPath,
        options: Options(responseType: ResponseType.bytes),
      );

      final downloaded = await tempFile.length();
      if (downloaded <= 0) {
        return const DatabaseBootstrapResult(
          errorMessage: 'Download fehlgeschlagen: Datei ist leer.',
        );
      }

      if (await dbFile.exists()) {
        await dbFile.delete();
      }
      await tempFile.rename(dbFile.path);
      _validateReadOnlyDatabase(dbFile.path);
      return DatabaseBootstrapResult(databasePath: dbFile.path);
    } catch (error) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      return DatabaseBootstrapResult(
        errorMessage: 'Download der SQLite-Datei fehlgeschlagen: $error',
      );
    }
  }

  Future<File> _resolveDatabaseFile() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final dbDirectory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}warehouse_data',
    );
    if (!await dbDirectory.exists()) {
      await dbDirectory.create(recursive: true);
    }
    return File(
      '${dbDirectory.path}${Platform.pathSeparator}${AppConstants.localWarehouseDbFileName}',
    );
  }

  bool _isValidDownloadUrl(String value) {
    if (value.isEmpty ||
        value.contains('HIER_DEIN_GITHUB_RELEASE_DOWNLOAD_LINK_EINFUEGEN')) {
      return false;
    }
    final uri = Uri.tryParse(value);
    if (uri == null) {
      return false;
    }
    return uri.hasScheme &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  void _validateReadOnlyDatabase(String path) {
    sqlite.Database? db;
    try {
      db = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
      db.select("SELECT name FROM sqlite_master WHERE type='table' LIMIT 1");
    } finally {
      db?.dispose();
    }
  }
}

