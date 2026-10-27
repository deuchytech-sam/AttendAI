import '../../../university/domain/entities/university_role.dart';
import '../repositories/auth_repository.dart';

class RegisterUniversityAccount {
  const RegisterUniversityAccount(this._repository);
  final AuthRepository _repository;

  Future<void> call({
    required String email,
    required String password,
    required String displayName,
    required String universityId,
    required UniversityRole requestedRole,
    String? matricNumber,
  }) => _repository.register(
    email: email,
    password: password,
    displayName: displayName,
    universityId: universityId,
    requestedRole: requestedRole,
    matricNumber: matricNumber,
  );
}
