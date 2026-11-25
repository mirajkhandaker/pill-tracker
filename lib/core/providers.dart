import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database_helper.dart';
import '../data/repositories/dose_log_repository.dart';
import '../data/repositories/medicine_repository.dart';
import '../data/repositories/prescription_repository.dart';
import '../data/repositories/schedule_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../services/text_scan_service.dart';

/// App-wide singletons and repositories, exposed through Riverpod so screens
/// and controllers can depend on them and be overridden in tests.

final databaseHelperProvider = Provider<DatabaseHelper>(
  (ref) => DatabaseHelper.instance,
);

final medicineRepositoryProvider = Provider<MedicineRepository>(
  (ref) => MedicineRepository(ref.watch(databaseHelperProvider)),
);

final scheduleRepositoryProvider = Provider<ScheduleRepository>(
  (ref) => ScheduleRepository(ref.watch(databaseHelperProvider)),
);

final doseLogRepositoryProvider = Provider<DoseLogRepository>(
  (ref) => DoseLogRepository(ref.watch(databaseHelperProvider)),
);

final prescriptionRepositoryProvider = Provider<PrescriptionRepository>(
  (ref) => PrescriptionRepository(ref.watch(databaseHelperProvider)),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseHelperProvider)),
);

/// On-device text recognition for prescription photos (overridden in tests).
final textScanServiceProvider = Provider<TextScanService>(
  (ref) => const TextScanService(),
);
