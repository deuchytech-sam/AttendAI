import '../repositories/university_repository.dart';

class RecordStudentCheckIn {
  const RecordStudentCheckIn(this._repository);
  final UniversityRepository _repository;

  Future<AttendanceActionResult> call() => _repository.checkIn();
}
