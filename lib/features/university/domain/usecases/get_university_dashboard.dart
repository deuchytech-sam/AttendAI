import '../entities/university_dashboard.dart';
import '../repositories/university_repository.dart';

class GetUniversityDashboard {
  const GetUniversityDashboard(this._repository);
  final UniversityRepository _repository;

  Future<UniversityDashboard> call() => _repository.getDashboard();
}
