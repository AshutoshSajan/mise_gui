import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/models/app_models.dart';

final dashboardProvider = FutureProvider<DashboardSnapshot>((ref) {
  ref.watch(appLocaleProvider);
  return ref.watch(dashboardRepositoryProvider).loadDashboard();
});
