import '../entities/university_dashboard.dart';
import '../repositories/university_repository.dart';

class ToggleAttendanceSession {
  const ToggleAttendanceSession(this._repository);
  final UniversityRepository _repository;

  Future<UniversityDashboard> call(String courseId) =>
      _repository.toggleSession(courseId);
}
