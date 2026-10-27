import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../auth/domain/entities/university_account.dart';
import '../../../university/domain/entities/course.dart';
import '../../../university/domain/entities/university_role.dart';
import '../../domain/entities/admin_dashboard.dart';

class FirestoreAdminDataSource {
  FirestoreAdminDataSource({
    required this._firestore,
    required this._auth,
    required this.account,
  });

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final UniversityAccount account;

  DocumentReference<Map<String, dynamic>> get _universityDocument =>
      _firestore.collection('universities').doc(account.universityId);

  Future<AdminDashboard> getDashboard() async {
    final pending = await _firestore
        .collection('users')
        .where('universityId', isEqualTo: account.universityId)
        .where('status', isEqualTo: 'pending')
        .get();
    final courses = await _universityDocument.collection('courses').get();

    final pendingAccounts =
        pending.docs.map((doc) {
          final data = doc.data();
          return PendingAccount(
            uid: doc.id,
            displayName: data['displayName'] as String? ?? '',
            email: data['email'] as String? ?? '',
            universityId: data['universityId'] as String? ?? '',
            requestedRole: switch (data['requestedRole']) {
              'lecturer' => UniversityRole.lecturer,
              _ => UniversityRole.student,
            },
            matricNumber: data['matricNumber'] as String?,
          );
        }).toList()..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );

    return AdminDashboard(
      pendingAccounts: pendingAccounts,
      courses: courses.docs
          .map(
            (doc) => Course(
              id: doc.id,
              name: doc.data()['name'] as String? ?? '',
              lecturer: doc.data()['lecturer'] as String? ?? '',
              schedule: doc.data()['schedule'] as String? ?? '',
            ),
          )
          .toList(),
    );
  }

  Future<AdminDashboard> approveAccount({
    required PendingAccount pendingAccount,
    required List<String> courseIds,
  }) async {
    final adminUid = _auth.currentUser?.uid;
    if (adminUid == null) throw StateError('Admin session has expired.');

    final profileRef = _firestore.collection('users').doc(pendingAccount.uid);
    final memberRef = _universityDocument
        .collection('members')
        .doc(pendingAccount.uid);
    await _firestore.runTransaction((transaction) async {
      final profile = await transaction.get(profileRef);
      final member = await transaction.get(memberRef);
      final data = profile.data();
      if (!profile.exists || data == null || data['status'] != 'pending') {
        throw StateError('This account is no longer pending approval.');
      }
      if (member.exists) {
        throw StateError('A membership already exists for this account.');
      }
      if (data['universityId'] != account.universityId ||
          data['requestedRole'] != pendingAccount.requestedRole.name) {
        throw StateError('Account details changed. Refresh and review again.');
      }

      transaction.set(memberRef, {
        'status': 'active',
        'role': pendingAccount.requestedRole.name,
        'courseIds': pendingAccount.requestedRole == UniversityRole.student
            ? courseIds
            : <String>[],
        'approvedBy': adminUid,
        'approvedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(profileRef, {'status': 'approved'});
    });
    return getDashboard();
  }
}
