import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
  FaceLivenessBiometricRepository get biometricRepository =>
      _biometricRepository;

  /// Exposes the liveness service for direct widget usage.
  FaceLivenessService get livenessService =>
      _biometricRepository.livenessService;

  /// The current user's UID.
  String get userId => _account.uid;

  /// The university ID loaded from the current user's profile.
  String get universityId => _account.universityId.trim();

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

    final memberRef = _firestore.doc(
      'universities/${_account.universityId}/members/${_account.uid}',
    );

    return memberRef.snapshots().asyncExpand((memberDoc) {
      final courseIds = (memberDoc.data()?['courseIds'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList();

      if (courseIds.isEmpty) {
        return const Stream.empty();
      }

      // Watch attendanceSessions for this student's courses
      String? lastOpenCourseId;
      return _collection('attendanceSessions')
          .where('courseId', whereIn: courseIds)
          .where('status', isEqualTo: 'open')
          .snapshots()
          .map((snapshot) {
            final now = DateTime.now();
            final activeDocs = snapshot.docs.where((doc) {
              final openedAt = doc.data()['openedAt'] as Timestamp?;
              return openedAt != null &&
                  now.difference(openedAt.toDate()) < const Duration(hours: 24);
            }).toList();
            if (activeDocs.isEmpty) {
              final previouslyOpen = lastOpenCourseId;
              lastOpenCourseId = null;
              return previouslyOpen == null
                  ? null
                  : SessionStatusChanged(
                      courseId: previouslyOpen,
                      courseName: '',
                      isOpen: false,
                    );
            }
            // Return the first open session (there should be at most one)
            final session = activeDocs.first;
            final data = session.data();
            lastOpenCourseId = data['courseId'] as String?;
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
    final courseIds = courseQuery.map((course) => course.id).toList();
    final students = _account.role == UniversityRole.lecturer
        ? await _loadDocumentsForCourseIds('students', courseIds)
        : (await _collection(
            'students',
          ).where('userId', isEqualTo: _account.uid).get()).docs;
    final allSessions = await _loadDocumentsForCourseIds(
      'attendanceSessions',
      courseIds,
    );
    final openSessions =
        allSessions.where((session) {
          final data = session.data();
          final openedAt = data['openedAt'] as Timestamp?;
          return data['status'] == 'open' &&
              openedAt != null &&
              DateTime.now().difference(openedAt.toDate()) <
                  const Duration(hours: 24);
        }).toList()..sort((a, b) {
          final aTime =
              (a.data()['openedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final bTime =
              (b.data()['openedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          return bTime.compareTo(aTime);
        });
    final records = _account.role == UniversityRole.lecturer
        ? await _loadRecordsForSessions(allSessions.map((s) => s.id).toList())
        : (await _collection(
            'attendanceRecords',
          ).where('studentUid', isEqualTo: _account.uid).get()).docs;

    return UniversityDashboard(
      courses: courseQuery.map(_courseFromDoc).toList(),
      students: students.map(_studentFromDoc).toList(),
      entries: records.map((doc) => _entryFromDoc(doc, allSessions)).toList(),
      openSessionCourseId: openSessions.isEmpty
          ? null
          : openSessions.first.data()['courseId'] as String?,
      openSessionId: openSessions.isEmpty ? null : openSessions.first.id,
    );
  }

  Future<List<DocumentSnapshot<Map<String, dynamic>>>> _loadCourses() async {
    if (_account.role == UniversityRole.lecturer) {
      final snapshot = await _collection('courses')
          .where('lecturerIds', arrayContains: _account.uid)
          .get();
      return snapshot.docs;
    }
    final member = await _firestore
        .doc('universities/${_account.universityId}/members/${_account.uid}')
        .get();
    final courseIds = (member.data()?['courseIds'] as List<dynamic>? ?? [])
        .whereType<String>()
        .toList();
    if (courseIds.isEmpty) return [];
    final snapshots = await Future.wait(
      courseIds.map((id) => _collection('courses').doc(id).get()),
    );
    return snapshots.where((snapshot) => snapshot.exists).toList();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _loadDocumentsForCourseIds(
    String collectionName,
    List<String> courseIds,
  ) async {
    if (courseIds.isEmpty) return [];
    final batches = <List<String>>[];
    for (var start = 0; start < courseIds.length; start += 30) {
      batches.add(courseIds.skip(start).take(30).toList());
    }
    final snapshots = await Future.wait(
      batches.map(
        (batch) =>
            _collection(collectionName).where('courseId', whereIn: batch).get(),
      ),
    );
    return snapshots.expand((snapshot) => snapshot.docs).toList();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _loadRecordsForSessions(List<String> sessionIds) async {
    final uniqueSessionIds = sessionIds.toSet().toList();
    if (uniqueSessionIds.isEmpty) return [];

    // Query one session at a time. A whereIn of many sessions makes Rules
    // resolve each record's session and course assignment in one request,
    // which can exceed Firestore's per-query document-access-call limit.
    final records = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (var start = 0; start < uniqueSessionIds.length; start += 5) {
      final sessionBatch = uniqueSessionIds.skip(start).take(5);
      final snapshots = await Future.wait(
        sessionBatch.map(
          (sessionId) =>
              _collection('attendanceRecords')
                  .where('sessionId', isEqualTo: sessionId)
                  .get(),
        ),
      );
      records.addAll(snapshots.expand((snapshot) => snapshot.docs));
    }
    return records;
  }

  /// Links a roster entry to its uniquely matching active student account.
  Future<Map<String, dynamic>> linkStudentRosterRecord(String studentId) async {
    final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable = functions.httpsCallable('linkStudentRosterRecord');
    final result = await callable.call({'studentId': studentId});
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Lecturer action: invalidates the student's current face templates so
  /// their next enrollment replaces them on their own device.
  Future<void> resetStudentFaceEnrollment(String studentId) async {
    final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable = functions.httpsCallable('resetStudentFaceEnrollment');
    await callable.call({'studentId': studentId});
  }

  Future<UniversityDashboard> toggleSession(String courseId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.uid != _account.uid) {
      debugPrint(
        '[SessionToggle] No matching Firebase Auth user is signed in.',
      );
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Sign in again to manage attendance sessions.',
      );
    }

    await currentUser.getIdToken(true);
    final appCheckToken = await FirebaseAppCheck.instance.getToken(true);
    debugPrint(
      '[SessionToggle] Authenticated user present; '
      'App Check token available=${appCheckToken != null}',
    );

    final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable = functions.httpsCallable('toggleAttendanceSession');

    late HttpsCallableResult<dynamic> result;
    try {
      result = await callable.call({
        'universityId': _account.universityId,
        'courseId': courseId,
      });
    } on FirebaseFunctionsException catch (error, stackTrace) {
      debugPrint(
        '[SessionToggle] Function failed: code=${error.code}, '
        'message=${error.message}, details=${error.details}\n$stackTrace',
      );
      rethrow;
    }

    final data = result.data as Map<String, dynamic>;
    final action = data['action'] as String? ?? 'unknown';

    // Refresh dashboard after session toggle
    final dashboard = await getDashboard();
    return dashboard;
  }

  /// Records attendance check-in via Cloud Function after face verification.
  /// Returns the updated dashboard and whether check-in was recorded.
  Future<AttendanceActionResult> checkIn({
    required String studentId,
    required String courseId,
    required List<List<double>> faceEmbeddings,
    required double faceMatchScore,
  }) async {
    final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable = functions.httpsCallable('recordAttendanceCheckIn');

    final result = await callable.call({
      'courseId': courseId,
      'faceEmbeddings': faceEmbeddings,
      'faceMatchScore': faceMatchScore,
    });

    final data = result.data as Map<String, dynamic>;
    final recorded = data['recorded'] as bool? ?? false;

    // Refresh dashboard after check-in
    final dashboard = await getDashboard();
    return AttendanceActionResult(dashboard: dashboard, recorded: recorded);
  }

  /// Lecturer: Gets attendance for a specific session with real-time updates.
  /// Returns a stream of SessionAttendance objects.
  /// Watches the most recently opened session for a course, including its attendance.
  Stream<SessionAttendance> watchLatestSessionAttendanceForCourse(
    String courseId,
  ) {
    final sessions = _collection('attendanceSessions')
        .where('courseId', isEqualTo: courseId)
        .snapshots();
    return sessions.asyncExpand((snapshot) {
      if (snapshot.docs.isEmpty) {
        return Stream.value(
          SessionAttendance(
            sessionId: '',
            courseId: courseId,
            status: 'closed',
            openedAt: null,
            closedAt: null,
            attendance: const [],
            totalStudents: 0,
            presentCount: 0,
            absentCount: 0,
          ),
        );
      }
      final latest = [...snapshot.docs]
        ..sort((a, b) {
          final aTime =
              (a.data()['openedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final bTime =
              (b.data()['openedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          return aTime.compareTo(bTime);
        });
      return watchSessionAttendance(latest.last.id);
    });
  }

  Stream<SessionAttendance> watchSessionAttendance(String sessionId) {
    final sessionsRef = _collection('attendanceSessions').doc(sessionId);
    final recordsRef = _collection('attendanceRecords')
        .where('sessionId', isEqualTo: sessionId);
    final studentsRef = _collection('students');

    // Combine streams using asyncExpand
    return sessionsRef.snapshots().asyncExpand((sessionDoc) async* {
      if (!sessionDoc.exists) {
        // Yield an empty attendance state instead of returning null
        yield SessionAttendance(
          sessionId: sessionId,
          courseId: '',
          status: 'closed',
          openedAt: null,
          closedAt: null,
          attendance: [],
          totalStudents: 0,
          presentCount: 0,
          absentCount: 0,
        );
        return;
      }

      final sessionData = sessionDoc.data()!;
      final courseId = sessionData['courseId'] as String;
      final openedAt = sessionData['openedAt'] is Timestamp
          ? (sessionData['openedAt'] as Timestamp).toDate()
          : null;
      final expired =
          sessionData['status'] == 'open' &&
          (openedAt == null ||
              DateTime.now().difference(openedAt) >= const Duration(hours: 24));

      // Get students for this course
      final studentsSnap = await studentsRef
          .where('courseId', isEqualTo: courseId)
          .get();
      final students = studentsSnap.docs.map(_studentFromDoc).toList();

      // Watch attendance records for this session
      yield* recordsRef.snapshots().map((recordsSnap) {
        final records = recordsSnap.docs.map((doc) => doc.data()).toList();

        final attendance = students.map((student) {
          final record = records.firstWhere(
            (r) => r['studentId'] == student.id,
            orElse: () => <String, dynamic>{},
          );
          return StudentAttendance(
            studentId: student.id,
            studentName: student.name,
            matricNumber: student.matricNumber,
            userId: student.userId,
            status: record.isNotEmpty ? 'present' : 'absent',
            checkedAt: record['checkedAt'] != null
                ? (record['checkedAt'] as Timestamp).toDate()
                : null,
            faceMatchScore: record['faceMatchScore'] != null
                ? (record['faceMatchScore'] as num).toDouble()
                : null,
            verificationProvider: record['verificationProvider'] as String?,
          );
        }).toList();

        return SessionAttendance(
          sessionId: sessionDoc.id,
          courseId: courseId,
          status: expired ? 'closed' : sessionData['status'] as String,
          openedAt: openedAt,
          closedAt: expired
              ? openedAt?.add(const Duration(hours: 24))
              : sessionData['closedAt'] != null
              ? (sessionData['closedAt'] as Timestamp).toDate()
              : null,
          attendance: attendance,
          totalStudents: students.length,
          presentCount: attendance.where((a) => a.status == 'present').length,
          absentCount: attendance.where((a) => a.status == 'absent').length,
        );
      });
    });
  }

  /// Lecturer: Gets semester attendance summary for a course.
  Future<SemesterAttendanceSummary> getSemesterAttendanceSummary({
    required String courseId,
    required DateTime semesterStart,
    required DateTime semesterEnd,
  }) async {
    final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable = functions.httpsCallable('getSemesterAttendanceSummary');

    final result = await callable.call({
      'universityId': universityId,
      'courseId': courseId,
      'semesterStart': semesterStart.toIso8601String(),
      'semesterEnd': semesterEnd.toIso8601String(),
    });

    final data = result.data as Map<String, dynamic>;
    return SemesterAttendanceSummary.fromMap(data);
  }

  /// Student: Gets own attendance history for a course.
  Future<StudentAttendanceHistory> getStudentAttendanceHistory({
    String? courseId,
    required DateTime semesterStart,
    required DateTime semesterEnd,
  }) async {
    final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable = functions.httpsCallable('getStudentAttendanceHistory');

    final result = await callable.call({
      'universityId': _account.universityId,
      if (courseId != null) 'courseId': courseId,
      'semesterStart': semesterStart.toIso8601String(),
      'semesterEnd': semesterEnd.toIso8601String(),
    });

    final data = result.data as Map<String, dynamic>;
    return StudentAttendanceHistory.fromMap(data);
  }

  /// Collection reference for face embeddings.
  CollectionReference<Map<String, dynamic>> get _faceEmbeddingsCollection =>
      _collection('faceEmbeddings');

  /// Saves face embeddings to Firestore for the given face ID (student's Firebase UID).
  /// Store each vector in a map because Firestore rejects nested arrays.
  Future<void> saveFaceEmbeddings({
    required String faceId,
    required List<List<double>> embeddings,
    required String studentId,
  }) async {
    final normalized = embeddings
        .map((vector) => vector.map((value) => value.toDouble()).toList())
        .toList();
    final encodedEmbeddings = normalized
        .map((vector) => <String, dynamic>{'vector': vector})
        .toList();
    debugPrint(
      '[FaceEmbeddings] Upload count=${normalized.length}, '
      'lengths=${normalized.map((vector) => vector.length).toList()}, '
      'payload=List<Map<String, List<double>>>',
    );
    await _faceEmbeddingsCollection.doc(faceId).set({
      'faceId': faceId,
      'studentId': studentId,
      'embeddings': encodedEmbeddings,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Loads face embeddings from Firestore for the given face ID.
  /// Returns the list of embeddings, or null if not found.
  Future<List<List<double>>?> loadFaceEmbeddings(String faceId) async {
    final doc = await _faceEmbeddingsCollection.doc(faceId).get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    final embeddings = data['embeddings'] as List<dynamic>?;
    if (embeddings == null || embeddings.isEmpty) return null;

    // Current format: [{vector: [double, ...]}, ...]. Also accept legacy
    // nested lists and a single flat vector for migration compatibility.
    if (embeddings.every((value) => value is num)) {
      return [embeddings.map((value) => (value as num).toDouble()).toList()];
    }
    return embeddings.map<List<double>>((value) {
      final vector = value is Map
          ? value['vector'] as List<dynamic>?
          : value as List<dynamic>?;
      if (vector == null || vector.any((item) => item is! num)) {
        throw StateError('Stored face embedding has an unsupported format.');
      }
      return vector.map((item) => (item as num).toDouble()).toList();
    }).toList();
  }

  /// Checks if face embeddings exist in Firestore for the given face ID.
  Future<bool> hasFaceEmbeddings(String faceId) async {
    final doc = await _faceEmbeddingsCollection.doc(faceId).get();
    if (!doc.exists) return false;
    final data = doc.data();
    final embeddings = data?['embeddings'];
    return data?['status'] != 'reset_required' &&
        embeddings is List &&
        embeddings.isNotEmpty;
  }

  /// Returns true when a lecturer has reset this student's face enrollment.
  Future<bool> isFaceEnrollmentResetRequired(String faceId) async {
    final doc = await _faceEmbeddingsCollection.doc(faceId).get();
    return doc.data()?['status'] == 'reset_required';
  }

  /// Deletes face embeddings from Firestore for the given face ID.
  Future<void> deleteFaceEmbeddings(String faceId) async {
    await _faceEmbeddingsCollection.doc(faceId).delete();
  }

  Course _courseFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Course(
      id: doc.id,
      name: data['name'] as String? ?? '',
      lecturer: data['lecturer'] as String? ?? '',
      schedule: data['schedule'] as String? ?? '',
      lecturerIds: (data['lecturerIds'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
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
    final faceMatchScore = data['faceMatchScore'] != null
        ? (data['faceMatchScore'] as num).toDouble()
        : null;
    return AttendanceEntry(
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      matricNumber: data['matricNumber'] as String? ?? '',
      sessionId: sessionId,
      courseId: courseIds.isEmpty ? '' : courseIds.first,
      checkedAt: timestamp?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
      verificationProvider: provider,
      faceMatchScore: faceMatchScore,
    );
  }
}

/// Represents a single student's attendance status for a session.
class StudentAttendance {
  const StudentAttendance({
    required this.studentId,
    required this.studentName,
    required this.matricNumber,
    required this.userId,
    required this.status, // 'present' or 'absent'
    this.checkedAt,
    this.faceMatchScore,
    this.verificationProvider,
  });

  final String studentId;
  final String studentName;
  final String matricNumber;
  final String? userId;
  final String status;
  final DateTime? checkedAt;
  final double? faceMatchScore;
  final String? verificationProvider;
}

/// Represents attendance for a full session (all students in the course).
class SessionAttendance {
  const SessionAttendance({
    required this.sessionId,
    required this.courseId,
    required this.status,
    required this.openedAt,
    required this.closedAt,
    required this.attendance,
    required this.totalStudents,
    required this.presentCount,
    required this.absentCount,
  });

  final String sessionId;
  final String courseId;
  final String status; // 'open' or 'closed'
  final DateTime? openedAt;
  final DateTime? closedAt;
  final List<StudentAttendance> attendance;
  final int totalStudents;
  final int presentCount;
  final int absentCount;

  double get attendancePercentage =>
      totalStudents > 0 ? (presentCount / totalStudents) * 100 : 0.0;
}

/// Represents a student's attendance summary for a semester.
class StudentSemesterSummary {
  const StudentSemesterSummary({
    required this.studentId,
    required this.studentName,
    required this.matricNumber,
    required this.userId,
    required this.sessionsAttended,
    required this.totalSessions,
    required this.percentage,
    required this.recentSessions,
  });

  final String studentId;
  final String studentName;
  final String matricNumber;
  final String? userId;
  final int sessionsAttended;
  final int totalSessions;
  final int percentage;
  final List<RecentSession> recentSessions;

  factory StudentSemesterSummary.fromMap(Map<String, dynamic> data) {
    return StudentSemesterSummary(
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      matricNumber: data['matricNumber'] as String? ?? '',
      userId: data['userId'] as String?,
      sessionsAttended: data['sessionsAttended'] as int? ?? 0,
      totalSessions: data['totalSessions'] as int? ?? 0,
      percentage: data['percentage'] as int? ?? 0,
      recentSessions: (data['recentSessions'] as List<dynamic>? ?? [])
          .map((e) => RecentSession.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// A recent session attended by a student.
class RecentSession {
  const RecentSession({
    required this.sessionId,
    required this.checkedAt,
    this.faceMatchScore,
  });

  final String sessionId;
  final String checkedAt;
  final double? faceMatchScore;

  factory RecentSession.fromMap(Map<String, dynamic> data) {
    return RecentSession(
      sessionId: data['sessionId'] as String? ?? '',
      checkedAt: data['checkedAt'] as String? ?? '',
      faceMatchScore: data['faceMatchScore'] != null
          ? (data['faceMatchScore'] as num).toDouble()
          : null,
    );
  }
}

/// Semester attendance summary for a course (lecturer view).
class SemesterAttendanceSummary {
  const SemesterAttendanceSummary({
    required this.courseId,
    required this.semesterStart,
    required this.semesterEnd,
    required this.totalSessions,
    required this.studentSummaries,
  });

  final String courseId;
  final String semesterStart;
  final String semesterEnd;
  final int totalSessions;
  final List<StudentSemesterSummary> studentSummaries;

  factory SemesterAttendanceSummary.fromMap(Map<String, dynamic> data) {
    return SemesterAttendanceSummary(
      courseId: data['courseId'] as String? ?? '',
      semesterStart: data['semesterStart'] as String? ?? '',
      semesterEnd: data['semesterEnd'] as String? ?? '',
      totalSessions: data['totalSessions'] as int? ?? 0,
      studentSummaries: (data['studentSummaries'] as List<dynamic>? ?? [])
          .map((e) => StudentSemesterSummary.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

extension StudentSemesterSummaryExtension on StudentSemesterSummary {}

extension RecentSessionExtension on RecentSession {}

/// Student's own attendance history for a course.
class StudentAttendanceHistory {
  const StudentAttendanceHistory({
    required this.studentId,
    required this.studentName,
    required this.matricNumber,
    required this.courseId,
    required this.semesterStart,
    required this.semesterEnd,
    required this.totalSessions,
    required this.attendedCount,
    required this.percentage,
    required this.history,
  });

  final String studentId;
  final String studentName;
  final String matricNumber;
  final String courseId;
  final String semesterStart;
  final String semesterEnd;
  final int totalSessions;
  final int attendedCount;
  final int percentage;
  final List<StudentHistoryEntry> history;

  factory StudentAttendanceHistory.fromMap(Map<String, dynamic> data) {
    return StudentAttendanceHistory(
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      matricNumber: data['matricNumber'] as String? ?? '',
      courseId: data['courseId'] as String? ?? '',
      semesterStart: data['semesterStart'] as String? ?? '',
      semesterEnd: data['semesterEnd'] as String? ?? '',
      totalSessions: data['totalSessions'] as int? ?? 0,
      attendedCount: data['attendedCount'] as int? ?? 0,
      percentage: data['percentage'] as int? ?? 0,
      history: (data['history'] as List<dynamic>? ?? [])
          .map((e) => StudentHistoryEntry.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// A single entry in a student's attendance history.
class StudentHistoryEntry {
  const StudentHistoryEntry({
    required this.sessionId,
    required this.courseId,
    required this.sessionDate,
    required this.sessionStatus,
    required this.checkedIn,
    this.checkedAt,
    this.faceMatchScore,
    this.verificationProvider,
  });

  final String sessionId;
  final String courseId;
  final String sessionDate;
  final String sessionStatus;
  final bool checkedIn;
  final String? checkedAt;
  final double? faceMatchScore;
  final String? verificationProvider;

  factory StudentHistoryEntry.fromMap(Map<String, dynamic> data) {
    return StudentHistoryEntry(
      sessionId: data['sessionId'] as String? ?? '',
      courseId: data['courseId'] as String? ?? '',
      sessionDate: data['sessionDate'] as String? ?? '',
      sessionStatus: data['sessionStatus'] as String? ?? '',
      checkedIn: data['checkedIn'] as bool? ?? false,
      checkedAt: data['checkedAt'] as String?,
      faceMatchScore: data['faceMatchScore'] != null
          ? (data['faceMatchScore'] as num).toDouble()
          : null,
      verificationProvider: data['verificationProvider'] as String?,
    );
  }
}
