import 'package:flutter_test/flutter_test.dart';
import 'package:attendai/features/university/domain/entities/course.dart';

void main() {
  group('Course lecturer assignments', () {
    test('lecturer IDs default to an empty list for legacy courses', () {
      const course = Course(
        id: 'course-1',
        name: 'Biology',
        lecturer: 'Dr. Legacy',
        schedule: 'Monday',
      );

      expect(course.lecturerIds, isEmpty);
      expect(course.lecturerNames(const {}), 'Dr. Legacy');
    });

    test(
      'assigned lecturer names come from IDs and missing users are safe',
      () {
        const course = Course(
          id: 'course-1',
          name: 'Biology',
          lecturer: 'Old display name',
          schedule: 'Monday',
          lecturerIds: ['active-id', 'deleted-id'],
        );

        expect(
          course.lecturerNames(const {'active-id': 'Dr. Active'}),
          'Dr. Active, Inactive lecturer',
        );
      },
    );

    test('unassigned courses have an explicit display state', () {
      const course = Course(
        id: 'course-1',
        name: 'Biology',
        lecturer: 'Unassigned',
        schedule: 'Monday',
      );

      expect(course.lecturerNames(const {}), 'No lecturer assigned');
    });
  });
}
