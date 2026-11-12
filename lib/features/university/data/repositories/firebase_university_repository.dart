import '../../domain/entities/university_dashboard.dart';
import '../../domain/repositories/university_repository.dart';
import '../datasources/firestore_university_data_source.dart';

class FirebaseUniversityRepository implements UniversityRepository {
  const FirebaseUniversityRepository(this._dataSource);
  final FirestoreUniversityDataSource _dataSource;

  @override
  Future<UniversityDashboard> getDashboard() => _dataSource.getDashboard();

  @override
  Future<UniversityDashboard> toggleSession(String courseId) =>
      _dataSource.toggleSession(courseId);

  @override
  Future<AttendanceActionResult> checkIn({
    required String studentId,
    required String courseId,
    required List<List<double>> faceEmbeddings,
    required double faceMatchScore,
  }) => _dataSource.checkIn(
    studentId: studentId,
    courseId: courseId,
    faceEmbeddings: faceEmbeddings,
    faceMatchScore: faceMatchScore,
  );

  @override
  Stream<SessionAttendance> watchSessionAttendance(String sessionId) =>
      _dataSource.watchSessionAttendance(sessionId);

  @override
  Future<SemesterAttendanceSummary> getSemesterAttendanceSummary({
    required String courseId,
    required DateTime semesterStart,
    required DateTime semesterEnd,
  }) => _dataSource.getSemesterAttendanceSummary(
    courseId: courseId,
    semesterStart: semesterStart,
    semesterEnd: semesterEnd,
  );

  @override
  Future<StudentAttendanceHistory> getStudentAttendanceHistory({
    String? courseId,
    required DateTime semesterStart,
    required DateTime semesterEnd,
  }) => _dataSource.getStudentAttendanceHistory(
    courseId: courseId,
    semesterStart: semesterStart,
    semesterEnd: semesterEnd,
  );
}
