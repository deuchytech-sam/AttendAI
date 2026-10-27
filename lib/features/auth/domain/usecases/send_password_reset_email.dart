import '../repositories/auth_repository.dart';

class SendPasswordResetEmail {
  const SendPasswordResetEmail(this._repository);
  final AuthRepository _repository;

  Future<void> call({required String email}) =>
      _repository.sendPasswordResetEmail(email: email);
}