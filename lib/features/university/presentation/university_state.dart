import 'package:equatable/equatable.dart';

import '../domain/entities/attendance_entry.dart';
import '../domain/entities/course.dart';
import '../domain/entities/university_dashboard.dart';
import '../domain/entities/university_student.dart';
import '../data/datasources/firestore_university_data_source.dart';

enum UniversityLoadStatus { initial, loading, loaded, failure }

class UniversityState extends Equatable {
  const UniversityState({
    this.status = UniversityLoadStatus.initial,
    this.courses = const [],
    this.students = const [],
    this.entries = const [],
    this.openSessionCourseId,
    this.openSessionId,
    this.errorMessage,
    this.actionMessage,
    // Lecturer attendance
    this.currentSessionAttendance,
    this.semesterAttendanceSummary,
    this.semesterSummaryError,
    this.isLoadingSessionAttendance = false,
    this.isLoadingSemesterSummary = false,
    // Student attendance history
    this.studentAttendanceHistory,
    this.isLoadingStudentHistory = false,
  });

  final UniversityLoadStatus status;
  final List<Course> courses;
  final List<UniversityStudent> students;
  final List<AttendanceEntry> entries;
  final String? openSessionCourseId;
  final String? openSessionId;
  final String? errorMessage;
  final String? actionMessage;

  // Lecturer attendance state
  final SessionAttendance? currentSessionAttendance;
  final SemesterAttendanceSummary? semesterAttendanceSummary;
  final String? semesterSummaryError;
  final bool isLoadingSessionAttendance;
  final bool isLoadingSemesterSummary;

  // Student attendance history state
  final StudentAttendanceHistory? studentAttendanceHistory;
  final bool isLoadingStudentHistory;

  UniversityState withDashboard(
    UniversityDashboard dashboard, {
    String? actionMessage,
  }) => UniversityState(
    status: UniversityLoadStatus.loaded,
    courses: dashboard.courses,
    students: dashboard.students,
    entries: dashboard.entries,
    openSessionCourseId: dashboard.openSessionCourseId,
    openSessionId: dashboard.openSessionId,
    actionMessage: actionMessage,
  );

  UniversityState copyWith({
    UniversityLoadStatus? status,
    List<Course>? courses,
    List<UniversityStudent>? students,
    List<AttendanceEntry>? entries,
    String? openSessionCourseId,
    String? openSessionId,
    String? errorMessage,
    String? actionMessage,
    SessionAttendance? currentSessionAttendance,
    SemesterAttendanceSummary? semesterAttendanceSummary,
    String? semesterSummaryError,
    bool clearSemesterSummaryError = false,
    bool? isLoadingSessionAttendance,
    bool? isLoadingSemesterSummary,
    StudentAttendanceHistory? studentAttendanceHistory,
    bool? isLoadingStudentHistory,
  }) => UniversityState(
    status: status ?? this.status,
    courses: courses ?? this.courses,
    students: students ?? this.students,
    entries: entries ?? this.entries,
    openSessionCourseId: openSessionCourseId ?? this.openSessionCourseId,
    openSessionId: openSessionId ?? this.openSessionId,
    errorMessage: errorMessage ?? this.errorMessage,
    actionMessage: actionMessage ?? this.actionMessage,
    currentSessionAttendance:
        currentSessionAttendance ?? this.currentSessionAttendance,
    semesterAttendanceSummary:
        semesterAttendanceSummary ?? this.semesterAttendanceSummary,
    semesterSummaryError: clearSemesterSummaryError
        ? null
        : semesterSummaryError ?? this.semesterSummaryError,
    isLoadingSessionAttendance:
        isLoadingSessionAttendance ?? this.isLoadingSessionAttendance,
    isLoadingSemesterSummary:
        isLoadingSemesterSummary ?? this.isLoadingSemesterSummary,
    studentAttendanceHistory:
        studentAttendanceHistory ?? this.studentAttendanceHistory,
    isLoadingStudentHistory:
        isLoadingStudentHistory ?? this.isLoadingStudentHistory,
  );

  int presentFor(String courseId) =>
      entries.where((entry) => entry.courseId == courseId).length;

  List<UniversityStudent> studentsFor(String courseId) =>
      students.where((student) => student.courseId == courseId).toList();

  @override
  List<Object?> get props => [
    status,
    courses,
    students,
    entries,
    openSessionCourseId,
    openSessionId,
    errorMessage,
    actionMessage,
    currentSessionAttendance,
    semesterAttendanceSummary,
    semesterSummaryError,
    isLoadingSessionAttendance,
    isLoadingSemesterSummary,
    studentAttendanceHistory,
    isLoadingStudentHistory,
  ];
}
