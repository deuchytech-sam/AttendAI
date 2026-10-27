import '../entities/university_dashboard.dart';
import '../repositories/university_repository.dart';

class AddUniversityCourse {
  const AddUniversityCourse(this._repository);
  final UniversityRepository _repository;

  Future<UniversityDashboard> call({
    required String name,
    required String lecturer,
    required String schedule,
  }) =>
      _repository.addCourse(name: name, lecturer: lecturer, schedule: schedule);
}
