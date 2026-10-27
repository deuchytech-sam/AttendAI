import '../../../university/domain/entities/university_role.dart';
import '../../domain/entities/university_account.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/firebase_auth_data_source.dart';

class FirebaseAuthRepository implements AuthRepository {
  const FirebaseAuthRepository(this._dataSource);
  final FirebaseAuthDataSource _dataSource;

  @override
  Stream<UniversityAccount?> watchAccount() => _dataSource.watchAccount();

  @override
  Future<UniversityAccount?> getCurrentAccount() =>
      _dataSource.getCurrentAccount();

  @override
  Future<void> signIn({required String email, required String password}) =>
      _dataSource.signIn(email: email, password: password);

  @override
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    required String universityId,
    required UniversityRole requestedRole,
    String? matricNumber,
  }) => _dataSource.register(
    email: email,
    password: password,
    displayName: displayName,
    universityId: universityId,
    requestedRole: requestedRole,
    matricNumber: matricNumber,
  );

  @override
  Future<void> resendEmailVerification() =>
      _dataSource.resendEmailVerification();

  @override
  Future<void> signOut() => _dataSource.signOut();

  @override
  Future<void> sendPasswordResetEmail({required String email}) =>
      _dataSource.sendPasswordResetEmail(email: email);
}
