import '../entities/university_dashboard.dart';
import '../repositories/university_repository.dart';

class EnrollUniversityStudent {
  const EnrollUniversityStudent(this._repository);
  final UniversityRepository _repository;

  Future<UniversityDashboard> call({
    required String name,
    required String matricNumber,
    required String courseId,
  }) => _repository.addStudent(
    name: name,
    matricNumber: matricNumber,
    courseId: courseId,
  );
}
