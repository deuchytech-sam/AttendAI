import '../entities/university_account.dart';
import '../repositories/auth_repository.dart';

class WatchUniversityAccount {
  const WatchUniversityAccount(this._repository);
  final AuthRepository _repository;

  Stream<UniversityAccount?> call() => _repository.watchAccount();
}
