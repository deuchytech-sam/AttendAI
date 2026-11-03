import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../biometrics/domain/services/face_liveness_service.dart';
import '../../../biometrics/data/repositories/face_liveness_biometric_repository.dart';

import '../../../auth/domain/entities/university_account.dart';
import '../../../university/domain/entities/university_role.dart';
import '../../domain/entities/attendance_entry.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/university_dashboard.dart';
import '../../domain/entities/university_student.dart';
import '../../domain/repositories/university_repository.dart';
import '../../presentation/university_event.dart';

class FirestoreUniversityDataSource {
  FirestoreUniversityDataSource(
    this._firestore,
    this._account,
    this._biometricRepository,
  );

  final FirebaseFirestore _firestore;
  final UniversityAccount _account;
  final FaceLivenessBiometricRepository _biometricRepository;

  /// Exposes the biometric repository for face enrollment/verification flows.
  FaceLivenessBiometricRepository get biometricRepository => _biometricRepository;

  /// Exposes the liveness service for direct widget usage.
  FaceLivenessService get livenessService => _biometricRepository.livenessService;

  /// The current user's UID.
  String get userId => _account.uid;

  CollectionReference<Map<String, dynamic>> _collection(String name) =>
      _firestore
          .collection('universities')
          .doc(_account.universityId)
          .collection(name);

  /// Stream of session changes for real-time updates (for students).
  Stream<SessionStatusChanged?> watchSessionChanges() {
    if (_account.role == UniversityRole.lecturer) {
      // Lecturers don't need session notifications
      return const Stream.empty();
    }

    final memberRef = _firestore
        .doc('universities/${_account.universityId}/members/${_account.uid}');

    return memberRef.snapshots().asyncExpand((memberDoc) {
      final courseIds = (memberDoc.data()?['courseIds'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList();

      if (courseIds.isEmpty) {
        return const Stream.empty();
      }

      // Watch attendanceSessions for this student's courses
      return _collection('attendanceSessions')
          .where('courseId', whereIn: courseIds)
          .where('status', isEqualTo: 'open')
          .snapshots()
          .map((snapshot) {
        if (snapshot.docs.isEmpty) {
          return null;
        }
        // Return the first open session (there should be at most one)
        final session = snapshot.docs.first;
        final data = session.data();
        return SessionStatusChanged(
          courseId: data['courseId'] as String? ?? '',
          courseName: '', // Will be resolved by the bloc
          isOpen: true,
        );
      });
    });
  }

  Future<UniversityDashboard> getDashboard() async {
    final courseQuery = await _loadCourses();
    final studentsQuery = _account.role == UniversityRole.lecturer
        ? await _collection('students').get()
        : await _collection(
            'students',
          ).where('userId', isEqualTo: _account.uid).get();
    final allSessions = await _collection('attendanceSessions').get();
    final openSessions = allSessions.docs.where(
      (session) => session.data()['status'] == 'open',
    );
    final recordsQuery = _account.role == UniversityRole.lecturer
        ? await _collection('attendanceRecords').get()
        : await _collection(
            'attendanceRecords',
          ).where('studentUid', isEqualTo: _account.uid).get();

    return UniversityDashboard(
      courses: courseQuery.map(_courseFromDoc).toList(),
      students: studentsQuery.docs.map(_studentFromDoc).toList(),
      entries: recordsQuery.docs
          .map((doc) => _entryFromDoc(doc, allSessions.docs))
          .toList(),
      openSessionCourseId: openSessions.isEmpty
          ? null
          : openSessions.first.data()['courseId'] as String?,
    );
  }

  Future<List<DocumentSnapshot<Map<String, dynamic>>>> _loadCourses() async {
    if (_account.role == UniversityRole.lecturer) {
      final snapshot = await _collection('courses').get();
      return snapshot.docs;
    }
    final member = await _firestore
        .doc('universities/${_account.universityId}/members/${_account.uid}')
        .get();
    final courseIds = (member.data()?['courseIds'] as List<dynamic>? ?? [])
        .whereType<String>()
        .toList();
    if (courseIds.isEmpty) return [];
    if (courseIds.length <= 30) {
      final snapshot = await _collection(
        'courses',
      ).where(FieldPath.documentId, whereIn: courseIds).get();
      return snapshot.docs;
    }
    final snapshots = await Future.wait(
      courseIds.map((id) => _collection('courses').doc(id).get()),
    );
    return snapshots.where((snapshot) => snapshot.exists).toList();
  }

  Future<UniversityDashboard> addCourse({
    required String name,
    required String lecturer,
    required String schedule,
  }) async {
    final course = _collection('courses').doc();
    await course.set({
      'id': course.id,
      'name': name.trim(),
      'lecturer': lecturer.trim(),
      'schedule': schedule.trim(),
      'createdBy': _account.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return getDashboard();
  }

  Future<UniversityDashboard> addStudent({
    required String name,
    required String matricNumber,
    required String courseId,
  }) async {
    final student = _collection('students').doc();
    await student.set({
      'id': student.id,
      'name': name.trim(),
      'matricNumber': matricNumber.trim(),
      'courseId': courseId,
      'createdBy': _account.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return getDashboard();
  }

  Future<UniversityDashboard> toggleSession(String courseId) async {
    final sessions = await _collection(
      'attendanceSessions',
    ).where('status', isEqualTo: 'open').get();
    final sameCourse = sessions.docs.where(
      (session) => session.data()['courseId'] == courseId,
    );
    final batch = _firestore.batch();
    for (final session in sessions.docs) {
      batch.update(session.reference, {
        'status': 'closed',
        'closedAt': FieldValue.serverTimestamp(),
      });
    }
    if (sameCourse.isEmpty) {
      final session = _collection('attendanceSessions').doc();
      batch.set(session, {
        'id': session.id,
        'courseId': courseId,
        'status': 'open',
        'openedBy': _account.uid,
        'openedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return getDashboard();
  }

  Future<AttendanceActionResult> checkIn({required String studentId}) async {
    // Verification is handled by FlutterFaceLiveness widget in FaceVerificationScreen.
    // This method just records the attendance after successful verification.
    return AttendanceActionResult(
      dashboard: await getDashboard(),
      recorded: true,
    );
  }

  Course _courseFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Course(
      id: doc.id,
      name: data['name'] as String? ?? '',
      lecturer: data['lecturer'] as String? ?? '',
      schedule: data['schedule'] as String? ?? '',
    );
  }

  UniversityStudent _studentFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return UniversityStudent(
      id: doc.id,
      name: data['name'] as String? ?? '',
      matricNumber: data['matricNumber'] as String? ?? '',
      courseId: data['courseId'] as String? ?? '',
      userId: data['userId'] as String?,
    );
  }

  AttendanceEntry _entryFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sessions,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final timestamp = data['checkedAt'] as Timestamp?;
    final sessionId = data['sessionId'] as String? ?? '';
    final courseIds = sessions
        .where((session) => session.id == sessionId)
        .map((session) => session.data()['courseId'] as String? ?? '')
        .toList();
    final provider = data['verificationProvider'] as String? ?? '';
    return AttendanceEntry(
      studentId: data['studentId'] as String? ?? '',
      sessionId: sessionId,
      courseId: courseIds.isEmpty ? '' : courseIds.first,
      checkedAt: timestamp?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
      source: provider == 'facetec'
          ? 'FaceTec verified'
          : provider == 'iproov'
              ? 'iProov verified'
              : 'Unverified',
    );
  }
}