import '../entities/admin_dashboard.dart';

abstract interface class AdminRepository {
  Future<AdminDashboard> getDashboard();

  Future<AdminDashboard> approveAccount({
    required PendingAccount account,
    required List<String> courseIds,
  });
}
