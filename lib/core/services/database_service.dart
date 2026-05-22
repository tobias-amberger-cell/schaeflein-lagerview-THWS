import 'database_service_base.dart';
import 'database_service_stub.dart'
    if (dart.library.io) 'database_service_io.dart'
    if (dart.library.js_interop) 'database_service_web.dart' as impl;

export 'database_service_base.dart';

DatabaseService createDatabaseService() => impl.createDatabaseService();

