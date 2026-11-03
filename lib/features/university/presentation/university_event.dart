import 'package:equatable/equatable.dart';

sealed class UniversityEvent extends Equatable {
  const UniversityEvent();

  @override
  List<Object?> get props => [];
}

final class UniversityDashboardRequested extends UniversityEvent {
  const UniversityDashboardRequested();
}

final class UniversityCourseAdded extends UniversityEvent {
  const UniversityCourseAdded({
    required this.name,
    required this.lecturer,
    required this.schedule,
  });

  final String name;
  final String lecturer;
  final String schedule;

  @override
  List<Object?> get props => [name, lecturer, schedule];
}

final class UniversityStudentEnrolled extends UniversityEvent {
  const UniversityStudentEnrolled({
    required this.name,
    required this.matricNumber,
    required this.courseId,
  });

  final String name;
  final String matricNumber;
  final String courseId;

  @override
  List<Object?> get props => [name, matricNumber, courseId];
}

final class AttendanceSessionToggled extends UniversityEvent {
  const AttendanceSessionToggled(this.courseId);
  final String courseId;

  @override
  List<Object?> get props => [courseId];
}

final class StudentCheckInRequested extends UniversityEvent {
  const StudentCheckInRequested();
}

/// Event fired when a session status changes (real-time update from Firestore).
final class SessionStatusChanged extends UniversityEvent {
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

/// Event to dismiss the action message banner without reloading the dashboard.
final class ActionMessageDismissed extends UniversityEvent {
  const ActionMessageDismissed();

  @override
  List<Object?> get props => [];
}
