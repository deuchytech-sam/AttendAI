import 'package:equatable/equatable.dart';

import 'attendance_entry.dart';
import 'course.dart';
import 'university_student.dart';

class UniversityDashboard extends Equatable {
  const UniversityDashboard({
    required this.courses,
    required this.students,
    required this.entries,
    required this.openSessionCourseId,
    required this.openSessionId,
  });

  final List<Course> courses;
  final List<UniversityStudent> students;
  final List<AttendanceEntry> entries;
  final String? openSessionCourseId;
  final String? openSessionId;

  @override
  List<Object?> get props => [
    courses,
    students,
    entries,
    openSessionCourseId,
    openSessionId,
  ];
}
