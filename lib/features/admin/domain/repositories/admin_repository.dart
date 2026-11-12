import '../entities/admin_dashboard.dart';

abstract interface class AdminRepository {
  Future<AdminDashboard> getDashboard();

  Future<AdminDashboard> saveCourse({
    required String? courseId,
    required String name,
    required String schedule,
    required List<String> lecturerIds,
  });

  Future<AdminDashboard> approveAccount({
    required PendingAccount account,
    required List<String> courseIds,
  });
}
