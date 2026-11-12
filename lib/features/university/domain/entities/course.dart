import 'package:equatable/equatable.dart';

class Course extends Equatable {
  const Course({
    required this.id,
    required this.name,
    required this.lecturer,
    required this.schedule,
    this.lecturerIds = const [],
  });

  final String id;
  final String name;
  final String lecturer;
  final String schedule;
  final List<String> lecturerIds;

  String lecturerNames(Map<String, String> namesById) {
    if (lecturerIds.isEmpty) {
      final legacyName = lecturer.trim();
      return legacyName.isEmpty || legacyName.toLowerCase() == 'unassigned'
          ? 'No lecturer assigned'
          : legacyName;
    }
    return lecturerIds.map((id) {
      final name = namesById[id]?.trim();
      return name == null || name.isEmpty ? 'Inactive lecturer' : name;
    }).join(', ');
  }

  @override
  List<Object?> get props => [id, name, lecturer, schedule, lecturerIds];
}
