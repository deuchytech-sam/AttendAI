import '../entities/admin_dashboard.dart';
import '../repositories/admin_repository.dart';

class SaveAdminCourse {
  const SaveAdminCourse(this._repository);

  final AdminRepository _repository;

  Future<AdminDashboard> call({
    required String? courseId,
    required String name,
    required String schedule,
    required List<String> lecturerIds,
  }) => _repository.saveCourse(
    courseId: courseId,
    name: name,
    schedule: schedule,
    lecturerIds: lecturerIds,
  );
}
