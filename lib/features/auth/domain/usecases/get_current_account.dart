import '../entities/university_account.dart';
import '../repositories/auth_repository.dart';

class GetCurrentAccount {
  const GetCurrentAccount(this._repository);
  final AuthRepository _repository;

  Future<UniversityAccount?> call() => _repository.getCurrentAccount();
}
