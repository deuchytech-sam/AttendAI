import '../../domain/repositories/biometric_repository.dart';

class EnrollStudentBiometric {
  const EnrollStudentBiometric(this._repository);
  final BiometricRepository _repository;

  Future<EnrollmentResult> call({
    required String universityId,
    required String studentId,
  }) => _repository.enrollStudent(
    universityId: universityId,
    studentId: studentId,
  );
}