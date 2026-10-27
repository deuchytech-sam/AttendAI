import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../university/domain/entities/university_role.dart';
import '../../domain/entities/university_account.dart';

class FirebaseAuthDataSource {
  FirebaseAuthDataSource(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<UniversityAccount?> watchAccount() => _auth.userChanges().asyncMap(
    (user) => user == null ? null : _loadAccount(user),
  );

  Future<UniversityAccount?> getCurrentAccount() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    await user.reload();
    final refreshedUser = _auth.currentUser;
    if (refreshedUser == null) return null;
    // University-admin access is held in a custom claim. Force a fresh token
    // after promotion so Firestore rules see the claim immediately.
    await refreshedUser.getIdToken(true);
    return _loadAccount(refreshedUser);
  }

  Future<void> signIn({required String email, required String password}) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user?.getIdToken(true);
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    required String universityId,
    required UniversityRole requestedRole,
    String? matricNumber,
  }) async {
    final normalizedUniversityId = universityId.trim();
    if (!_isValidDocumentId(normalizedUniversityId)) {
      throw ArgumentError.value(
        universityId,
        'universityId',
        'Enter a valid university ID without a slash.',
      );
    }

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user!;
    await user.updateDisplayName(displayName.trim());
    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'email': user.email,
      'displayName': displayName.trim(),
      'universityId': normalizedUniversityId,
      'requestedRole': requestedRole.name,
      'matricNumber': matricNumber?.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await user.sendEmailVerification();
    await user.reload();
  }

  Future<void> resendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before requesting verification.');
    }
    await user.sendEmailVerification();
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordResetEmail({required String email}) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<UniversityAccount> _loadAccount(User user) async {
    final profile = await _firestore.collection('users').doc(user.uid).get();
    final data = profile.data() ?? const <String, dynamic>{};
    final universityId = data['universityId'] as String? ?? '';
    final requestedRole =
        _roleFrom(data['requestedRole']) ?? UniversityRole.student;

    Map<String, dynamic>? member;
    // A malformed value in an older profile must not break sign-in. Treat it
    // as pending so the account can be corrected by a university admin.
    if (_isValidDocumentId(universityId)) {
      final membership = await _firestore
          .doc('universities/$universityId/members/${user.uid}')
          .get();
      member = membership.data();
    }
    final active = user.emailVerified && member?['status'] == 'active';
    final approvedRole = active ? _roleFrom(member?['role']) : null;

    return UniversityAccount(
      uid: user.uid,
      email: user.email ?? '',
      displayName: data['displayName'] as String? ?? user.displayName ?? '',
      universityId: universityId,
      requestedRole: requestedRole,
      role: approvedRole,
      matricNumber: data['matricNumber'] as String?,
      status: active && approvedRole != null
          ? AccountStatus.active
          : AccountStatus.pending,
      emailVerified: user.emailVerified,
    );
  }

  UniversityRole? _roleFrom(Object? role) => switch (role) {
    'lecturer' => UniversityRole.lecturer,
    'student' => UniversityRole.student,
    'admin' => UniversityRole.admin,
    _ => null,
  };

  bool _isValidDocumentId(String value) =>
      value.isNotEmpty && !value.contains('/');
}
