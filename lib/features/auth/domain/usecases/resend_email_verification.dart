import '../repositories/auth_repository.dart';

class ResendEmailVerification {
  const ResendEmailVerification(this._repository);
  final AuthRepository _repository;

  Future<void> call() => _repository.resendEmailVerification();
}
