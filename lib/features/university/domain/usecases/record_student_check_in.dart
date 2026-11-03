import '../repositories/university_repository.dart';

class RecordStudentCheckIn {
  const RecordStudentCheckIn(this._repository);
  final UniversityRepository _repository;

  Future<AttendanceActionResult> call({required String studentId}) =>
      _repository.checkIn(studentId: studentId);
}
