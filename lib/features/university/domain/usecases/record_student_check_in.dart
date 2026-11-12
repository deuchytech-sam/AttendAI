import '../repositories/university_repository.dart';

class RecordStudentCheckIn {
  const RecordStudentCheckIn(this._repository);
  final UniversityRepository _repository;

  Future<AttendanceActionResult> call({
    required String studentId,
    required String courseId,
    required List<List<double>> faceEmbeddings,
    required double faceMatchScore,
  }) =>
      _repository.checkIn(
        studentId: studentId,
        courseId: courseId,
        faceEmbeddings: faceEmbeddings,
        faceMatchScore: faceMatchScore,
      );
}
