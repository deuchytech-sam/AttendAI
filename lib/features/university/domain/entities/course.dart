import 'package:equatable/equatable.dart';

class Course extends Equatable {
  const Course({
    required this.id,
    required this.name,
    required this.lecturer,
    required this.schedule,
  });

  final String id;
  final String name;
  final String lecturer;
  final String schedule;

  @override
  List<Object?> get props => [id, name, lecturer, schedule];
}
