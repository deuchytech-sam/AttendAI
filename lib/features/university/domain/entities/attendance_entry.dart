import 'package:equatable/equatable.dart';

class AttendanceEntry extends Equatable {
  const AttendanceEntry({
    required this.studentId,
    required this.sessionId,
    required this.courseId,
    required this.checkedAt,
    required this.source,
  });

  final String studentId;
  final String sessionId;
  final String courseId;
  final DateTime checkedAt;
  final String source;

  @override
  List<Object?> get props => [
    studentId,
    sessionId,
    courseId,
    checkedAt,
    source,
  ];
}
