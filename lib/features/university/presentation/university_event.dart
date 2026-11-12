import 'package:equatable/equatable.dart';

import '../data/datasources/firestore_university_data_source.dart';

/// Base class for all university events.
abstract class UniversityEvent extends Equatable {
  const UniversityEvent();

  @override
  List<Object?> get props => [];
}

/// Request to load the university dashboard.
class UniversityDashboardRequested extends UniversityEvent {
  const UniversityDashboardRequested();
}

/// Attendance session toggled (opened/closed).
class AttendanceSessionToggled extends UniversityEvent {
  const AttendanceSessionToggled(this.courseId);

  final String courseId;

  @override
  List<Object?> get props => [courseId];
}

/// Student check-in requested.
class StudentCheckInRequested extends UniversityEvent {
  const StudentCheckInRequested();

  @override
  List<Object?> get props => [];
}

/// Session status changed (opened/closed) - emitted from stream.
class SessionStatusChanged extends UniversityEvent {
  const SessionStatusChanged({
    required this.courseId,
    required this.courseName,
    required this.isOpen,
  });

  final String courseId;
  final String courseName;
  final bool isOpen;

  @override
  List<Object?> get props => [courseId, courseName, isOpen];
}

/// Action message dismissed.
class ActionMessageDismissed extends UniversityEvent {
  const ActionMessageDismissed();

  @override
  List<Object?> get props => [];
}

/// Session attendance requested (for lecturer live view).
class SessionAttendanceRequested extends UniversityEvent {
  const SessionAttendanceRequested(this.sessionId, {this.courseId});

  final String sessionId;
  final String? courseId;

  @override
  List<Object?> get props => [sessionId, courseId];
}

/// Session attendance updated (real-time stream).
class SessionAttendanceUpdated extends UniversityEvent {
  const SessionAttendanceUpdated(this.sessionAttendance);

  final SessionAttendance sessionAttendance;

  @override
  List<Object?> get props => [sessionAttendance];
}

/// Semester attendance summary requested.
class SemesterAttendanceSummaryRequested extends UniversityEvent {
  const SemesterAttendanceSummaryRequested({
    required this.courseId,
    required this.semesterStart,
    required this.semesterEnd,
  });

  final String courseId;
  final DateTime semesterStart;
  final DateTime semesterEnd;

  @override
  List<Object?> get props => [courseId, semesterStart, semesterEnd];
}

/// Semester attendance summary loaded.
class SemesterAttendanceSummaryLoaded extends UniversityEvent {
  const SemesterAttendanceSummaryLoaded(this.summary);

  final SemesterAttendanceSummary summary;

  @override
  List<Object?> get props => [summary];
}

/// Student attendance history requested.
class StudentAttendanceHistoryRequested extends UniversityEvent {
  const StudentAttendanceHistoryRequested({
    this.courseId,
    required this.semesterStart,
    required this.semesterEnd,
  });

  final String? courseId;
  final DateTime semesterStart;
  final DateTime semesterEnd;

  @override
  List<Object?> get props => [courseId, semesterStart, semesterEnd];
}

/// Student attendance history loaded.
class StudentAttendanceHistoryLoaded extends UniversityEvent {
  const StudentAttendanceHistoryLoaded(this.history);

  final StudentAttendanceHistory history;

  @override
  List<Object?> get props => [history];
}
