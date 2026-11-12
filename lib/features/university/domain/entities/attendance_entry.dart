import 'package:equatable/equatable.dart';

class AttendanceEntry extends Equatable {
  const AttendanceEntry({
    required this.studentId,
    required this.studentName,
    required this.matricNumber,
    required this.sessionId,
    required this.courseId,
    required this.checkedAt,
    required this.verificationProvider,
    this.faceMatchScore,
  });

  final String studentId;
  final String studentName;
  final String matricNumber;
  final String sessionId;
  final String courseId;
  final DateTime checkedAt;
  final String verificationProvider;
  final double? faceMatchScore;

  @override
  List<Object?> get props => [
    studentId,
    studentName,
    matricNumber,
    sessionId,
    courseId,
    checkedAt,
    verificationProvider,
    faceMatchScore,
  ];
}
