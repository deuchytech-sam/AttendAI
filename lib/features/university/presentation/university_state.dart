import 'package:equatable/equatable.dart';

import '../domain/entities/attendance_entry.dart';
import '../domain/entities/course.dart';
import '../domain/entities/university_dashboard.dart';
import '../domain/entities/university_student.dart';

enum UniversityLoadStatus { initial, loading, loaded, failure }

class UniversityState extends Equatable {
  const UniversityState({
    this.status = UniversityLoadStatus.initial,
    this.courses = const [],
    this.students = const [],
    this.entries = const [],
    this.openSessionCourseId,
    this.errorMessage,
    this.actionMessage,
  });

  final UniversityLoadStatus status;
  final List<Course> courses;
  final List<UniversityStudent> students;
  final List<AttendanceEntry> entries;
  final String? openSessionCourseId;
  final String? errorMessage;
  final String? actionMessage;

  UniversityState withDashboard(
    UniversityDashboard dashboard, {
    String? actionMessage,
  }) => UniversityState(
    status: UniversityLoadStatus.loaded,
    courses: dashboard.courses,
    students: dashboard.students,
    entries: dashboard.entries,
    openSessionCourseId: dashboard.openSessionCourseId,
    actionMessage: actionMessage,
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
    errorMessage,
    actionMessage,
  ];
}
