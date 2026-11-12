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
    final results = await Future.wait([
      _universityDocument
          .collection('members')
          .where('status', isEqualTo: 'active')
          .where('role', isEqualTo: 'lecturer')
          .get(),
      _firestore
          .collection('users')
          .where('universityId', isEqualTo: account.universityId)
          .where('status', isEqualTo: 'approved')
          .where('requestedRole', isEqualTo: 'lecturer')
          .get(),
    ]);
    final lecturerMembers = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final lecturerProfiles = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final profilesByUid = {
      for (final profile in lecturerProfiles.docs) profile.id: profile.data(),
    };

    // Membership controls active eligibility. The approved profile query
    // supplies the registered lecturer's name and email for the selector.
    // Requiring both avoids assigning a deactivated or deleted account.
    final lecturers =
        lecturerMembers.docs
            .where((member) => profilesByUid.containsKey(member.id))
            .map((member) {
              final data = profilesByUid[member.id]!;
              return UniversityAccount(
                uid: member.id,
                email: data['email'] as String? ?? '',
                displayName: data['displayName'] as String? ?? '',
                universityId: account.universityId,
                requestedRole: UniversityRole.lecturer,
                role: UniversityRole.lecturer,
                status: AccountStatus.active,
                emailVerified: data['emailVerified'] as bool? ?? false,
              );
            })
            .toList()
          ..sort(
            (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
          );

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
              lecturerIds: (doc.data()['lecturerIds'] as List<dynamic>? ?? [])
                  .whereType<String>()
                  .toList(),
            ),
          )
          .toList(),
      lecturers: lecturers,
    );
  }

  Future<AdminDashboard> saveCourse({
    required String? courseId,
    required String name,
    required String schedule,
    required List<String> lecturerIds,
  }) async {
    if (account.role != UniversityRole.admin) {
      throw StateError('Only a university admin can manage courses.');
    }
    final adminUid = _auth.currentUser?.uid;
    if (adminUid == null) throw StateError('Admin session has expired.');
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) throw StateError('Enter a course name.');

    final ids = lecturerIds.toSet().toList();
    if (ids.length > 8) {
      throw StateError('A course can have at most 8 assigned lecturers.');
    }
    final isCreate = courseId == null || courseId.isEmpty;
    final courseRef = isCreate
        ? _universityDocument.collection('courses').doc()
        : _universityDocument.collection('courses').doc(courseId);
    final memberRefs = ids
        .map((id) => _universityDocument.collection('members').doc(id))
        .toList();

    await _firestore.runTransaction((transaction) async {
      final currentCourse = isCreate ? null : await transaction.get(courseRef);
      if (currentCourse != null && !currentCourse.exists) {
        throw StateError(
          'This course no longer exists. Refresh and try again.',
        );
      }

      final members = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final memberRef in memberRefs) {
        members.add(await transaction.get(memberRef));
      }
      for (final member in members) {
        final data = member.data();
        if (!member.exists ||
            data?['status'] != 'active' ||
            data?['role'] != 'lecturer') {
          throw StateError('Every assigned lecturer must be active.');
        }
      }

      final fields = <String, dynamic>{
        'name': normalizedName,
        'schedule': schedule.trim(),
        'lecturerIds': ids,
      };
      if (isCreate) {
        transaction.set(courseRef, {
          'id': courseRef.id,
          ...fields,
          'lecturer': '',
          'createdBy': adminUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.update(courseRef, fields);
      }
    });

    return getDashboard();
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
        'displayName': pendingAccount.displayName,
        'email': pendingAccount.email,
        'courseIds': pendingAccount.requestedRole == UniversityRole.student
            ? courseIds
            : <String>[],
        'approvedBy': adminUid,
        'approvedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(profileRef, {'status': 'approved'});

      // If student, link their Firebase Auth UID to their student document
      if (pendingAccount.requestedRole == UniversityRole.student &&
          pendingAccount.matricNumber != null &&
          pendingAccount.matricNumber!.isNotEmpty) {
        final studentsQuery = await _universityDocument
            .collection('students')
            .where('matricNumber', isEqualTo: pendingAccount.matricNumber!)
            .limit(1)
            .get();
        if (studentsQuery.docs.isNotEmpty) {
          final rosterStudent = studentsQuery.docs.first;
          final linkedUserId = rosterStudent.data()['userId'];
          // A roster row may already belong to a different account. Do not
          // replace that link as a side effect of approving this request.
          if (linkedUserId == null || linkedUserId == pendingAccount.uid) {
            transaction.update(rosterStudent.reference, {
              'userId': pendingAccount.uid,
            });
          }
        }
      }
    });
    return getDashboard();
  }
}
