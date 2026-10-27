import '../../domain/entities/university_dashboard.dart';
import '../../domain/repositories/university_repository.dart';
import '../datasources/firestore_university_data_source.dart';

class FirebaseUniversityRepository implements UniversityRepository {
  const FirebaseUniversityRepository(this._dataSource);
  final FirestoreUniversityDataSource _dataSource;

  @override
  Future<UniversityDashboard> getDashboard() => _dataSource.getDashboard();

  @override
  Future<UniversityDashboard> addCourse({
    required String name,
    required String lecturer,
    required String schedule,
  }) =>
      _dataSource.addCourse(name: name, lecturer: lecturer, schedule: schedule);

  @override
  Future<UniversityDashboard> addStudent({
    required String name,
    required String matricNumber,
    required String courseId,
  }) => _dataSource.addStudent(
    name: name,
    matricNumber: matricNumber,
    courseId: courseId,
  );

  @override
  Future<UniversityDashboard> toggleSession(String courseId) =>
      _dataSource.toggleSession(courseId);

  @override
  Future<AttendanceActionResult> checkIn() => _dataSource.checkIn();
}
