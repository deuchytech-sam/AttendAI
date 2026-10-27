import '../entities/university_dashboard.dart';

abstract interface class UniversityRepository {
  Future<UniversityDashboard> getDashboard();

  Future<UniversityDashboard> addCourse({
    required String name,
    required String lecturer,
    required String schedule,
  });

  Future<UniversityDashboard> addStudent({
    required String name,
    required String matricNumber,
    required String courseId,
  });

  Future<UniversityDashboard> toggleSession(String courseId);

  Future<AttendanceActionResult> checkIn();
}

class AttendanceActionResult {
  const AttendanceActionResult({
    required this.dashboard,
    required this.recorded,
  });

  final UniversityDashboard dashboard;
  final bool recorded;
}
