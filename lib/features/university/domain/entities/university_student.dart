import 'package:equatable/equatable.dart';

class UniversityStudent extends Equatable {
  const UniversityStudent({
    required this.id,
    required this.name,
    required this.matricNumber,
    required this.courseId,
    this.userId,
  });

  final String id;
  final String name;
  final String matricNumber;
  final String courseId;
  final String? userId;

  @override
  List<Object?> get props => [id, name, matricNumber, courseId, userId];
}
