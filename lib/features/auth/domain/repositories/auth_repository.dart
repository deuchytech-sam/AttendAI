import '../entities/university_account.dart';
import '../../../university/domain/entities/university_role.dart';

abstract interface class AuthRepository {
  Stream<UniversityAccount?> watchAccount();
  Future<UniversityAccount?> getCurrentAccount();

  Future<void> signIn({required String email, required String password});

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    required String universityId,
    required UniversityRole requestedRole,
    String? matricNumber,
  });

  Future<void> sendPasswordResetEmail({required String email});

  Future<void> resendEmailVerification();
  Future<void> signOut();
}
