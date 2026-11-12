import '../entities/university_dashboard.dart';
import '../../data/datasources/firestore_university_data_source.dart';

abstract interface class UniversityRepository {
  Future<UniversityDashboard> getDashboard();

  Future<UniversityDashboard> toggleSession(String courseId);

  Future<AttendanceActionResult> checkIn({
    required String studentId,
    required String courseId,
    required List<List<double>> faceEmbeddings,
    required double faceMatchScore,
  });

  // Lecturer: Watch attendance for a specific session (real-time)
  Stream<SessionAttendance> watchSessionAttendance(String sessionId);

  // Lecturer: Get semester attendance summary for a course
  Future<SemesterAttendanceSummary> getSemesterAttendanceSummary({
    required String courseId,
    required DateTime semesterStart,
    required DateTime semesterEnd,
  });

  // Student: Get own attendance history
  Future<StudentAttendanceHistory> getStudentAttendanceHistory({
    String? courseId,
    required DateTime semesterStart,
    required DateTime semesterEnd,
  });
}

class AttendanceActionResult {
  const AttendanceActionResult({
    required this.dashboard,
    required this.recorded,
  });

  final UniversityDashboard dashboard;
  final bool recorded;
}
