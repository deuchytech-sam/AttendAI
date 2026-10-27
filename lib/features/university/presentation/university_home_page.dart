import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../app/injection_container.dart';
import '../../../app/theme/app_theme.dart';
import '../domain/entities/attendance_entry.dart';
import '../domain/entities/course.dart';
import '../domain/entities/university_role.dart';
import '../domain/entities/university_student.dart';
import 'university_bloc.dart';
import 'university_event.dart';
import 'university_state.dart';

class UniversityHomePage extends StatefulWidget {
  const UniversityHomePage({
    super.key,
    required this.role,
    required this.displayName,
    required this.universityId,
    required this.onSignOut,
    this.matricNumber,
  });

  final UniversityRole role;
  final String displayName;
  final String universityId;
  final VoidCallback onSignOut;
  final String? matricNumber;

  @override
  State<UniversityHomePage> createState() => _UniversityHomePageState();
}

class _UniversityHomePageState extends State<UniversityHomePage> {
  int _tab = 0;
  UniversityRole get _role => widget.role;
  String get _universityId => widget.universityId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.teal,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.fact_check_rounded,
                color: Colors.white,
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AttendAI',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.4,
                  ),
                ),
                Text(
                  'UNIVERSITY',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: Color(0xFF74848A),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _notice('Notifications will appear here.'),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            onPressed: widget.onSignOut,
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: Tooltip(
              message: '${widget.displayName} · ${_role.name}',
              child: CircleAvatar(
                backgroundColor: const Color(0xFFDCEFEB),
                foregroundColor: AppTheme.teal,
                child: Text(
                  widget.displayName
                      .trim()
                      .split(RegExp(r'\s+'))
                      .where((part) => part.isNotEmpty)
                      .take(2)
                      .map((part) => part[0].toUpperCase())
                      .join(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: BlocConsumer<UniversityBloc, UniversityState>(
          listener: (context, state) {
            final message = state.actionMessage ?? state.errorMessage;
            if (state.status == UniversityLoadStatus.loaded &&
                message != null) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(message)));
            }
          },
          builder: (context, state) {
            if (state.status == UniversityLoadStatus.loading ||
                state.status == UniversityLoadStatus.initial) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.status == UniversityLoadStatus.failure) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.errorMessage ??
                            'Could not load the university dashboard.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => context.read<UniversityBloc>().add(
                          const UniversityDashboardRequested(),
                        ),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              );
            }
            return IndexedStack(
              index: _tab,
              children: [
                _OverviewPage(
                  role: _role,
                  displayName: widget.displayName,
                  onAddStudent: _addStudent,
                  onAddCourse: _addCourse,
                  onOpenAttendance: () => setState(() => _tab = 2),
                  matricNumber: widget.matricNumber,
                ),
                _CoursesPage(
                  role: _role,
                  onAddCourse: _addCourse,
                  onAddStudent: _addStudent,
                ),
                _AttendancePage(role: _role, onEnrollFace: _showEnrollmentDialog),
                _ReportsPage(role: _role),
                if (_role == UniversityRole.lecturer) _StudentsPage(),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Overview',
          ),
          const NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            label: 'Courses',
          ),
          const NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            label: 'Attendance',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bar_chart_rounded),
            label: 'Reports',
          ),
          if (_role == UniversityRole.lecturer)
            const NavigationDestination(
              icon: Icon(Icons.people_alt_outlined),
              label: 'Students',
            ),
        ],
      ),
    );
  }

  void _notice(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _addCourse() async {
    final values = await _textFields(
      context,
      title: 'Add a course',
      fields: const [
        ('Course title', 'e.g. CSC 305 · Algorithms'),
        ('Lecturer', 'Lecturer name'),
        ('Schedule and venue', 'e.g. Thu · 11:00 AM · LT 1'),
      ],
    );
    if (values == null || values[0].isEmpty) return;
    if (!mounted) return;
    context.read<UniversityBloc>().add(
      UniversityCourseAdded(
        name: values[0],
        lecturer: values[1].isEmpty ? 'Unassigned' : values[1],
        schedule: values[2].isEmpty ? 'Schedule to be announced' : values[2],
      ),
    );
  }

  Future<void> _addStudent() async {
    final state = context.read<UniversityBloc>().state;
    final values = await _studentFields(context, state.courses);
    if (values == null || values[0].isEmpty || values[1].isEmpty) return;
    if (!mounted) return;
    context.read<UniversityBloc>().add(
      UniversityStudentEnrolled(
        name: values[0],
        matricNumber: values[1],
        courseId: values[2],
      ),
    );
  }

  Future<void> _showEnrollmentDialog(String studentId) async {
    final enrollmentUsecase = createEnrollStudentBiometric();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enroll Face'),
        content: const Text(
          'This will scan your face to create a secure biometric profile for attendance verification. '
          'Your face data is processed by iProov and never stored on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enroll'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await enrollmentUsecase(
        universityId: _universityId,
        studentId: studentId,
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (result.success) {
        _notice('Face enrolled successfully! You can now verify your attendance.');
      } else {
        _notice('Enrollment failed: ${result.errorMessage ?? 'Unknown error'}');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      _notice('Enrollment failed: $e');
    }
  }
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({
    required this.role,
    required this.displayName,
    required this.onAddStudent,
    required this.onAddCourse,
    required this.onOpenAttendance,
    this.matricNumber,
  });
  final UniversityRole role;
  final String displayName;
  final VoidCallback onAddStudent;
  final VoidCallback onAddCourse;
  final VoidCallback onOpenAttendance;
  final String? matricNumber;

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<UniversityBloc, UniversityState>(
    builder: (context, state) {
      final isLecturer = role == UniversityRole.lecturer;
      final ownStudent = state.students.isEmpty ? null : state.students.first;
      final total = isLecturer
          ? state.students.length
          : (ownStudent == null ? 0 : 1);
      final present = isLecturer
          ? state.entries.length
          : ownStudent == null
          ? 0
          : state.entries
                .where((entry) => entry.studentId == ownStudent.id)
                .length;
      final rate = total == 0 ? 0 : (present * 100 / total).round();
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        children: [
          Text(
            DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
            style: const TextStyle(
              color: Color(0xFF71808A),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isLecturer ? 'Welcome, $displayName' : 'Welcome back, $displayName',
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
              letterSpacing: -.7,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isLecturer
                ? 'Here’s your university attendance overview.'
                : 'Here’s your course schedule and attendance.',
            style: const TextStyle(color: Color(0xFF75838B)),
          ),
          const SizedBox(height: 18),
          _AttendanceHero(
            role: role,
            rate: rate,
            present: present,
            total: total,
            onOpenAttendance: onOpenAttendance,
          ),
          const SizedBox(height: 22),
          _SectionHeading(
            title: isLecturer ? 'University overview' : 'My semester',
          ),
          const SizedBox(height: 12),
          if (isLecturer)
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.people_alt_outlined,
                    label: 'Students',
                    value: '${state.students.length}',
                    tint: const Color(0xFFE9F3F1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    icon: Icons.menu_book_rounded,
                    label: 'Courses',
                    value: '${state.courses.length}',
                    tint: const Color(0xFFEEF0FA),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    icon: Icons.sensors_rounded,
                    label: 'Live',
                    value: state.openSessionCourseId == null ? '0' : '1',
                    tint: const Color(0xFFFFF4E7),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.menu_book_rounded,
                    label: 'My courses',
                    value: '${state.courses.length}',
                    tint: const Color(0xFFEEF0FA),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    icon: Icons.badge_outlined,
                    label: 'Matric no.',
                    value: matricNumber ?? ownStudent?.matricNumber ?? 'Pending',
                    tint: const Color(0xFFE9F3F1),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 22),
          _SectionHeading(
            title: isLecturer ? 'Lecturer actions' : 'Quick actions',
          ),
          const SizedBox(height: 12),
          if (isLecturer)
            Row(
              children: [
                Expanded(
                  child: _QuickAction(
                    icon: Icons.person_add_alt_1_rounded,
                    label: 'Enroll student',
                    onTap: onAddStudent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.add_circle_outline_rounded,
                    label: 'Add course',
                    onTap: onAddCourse,
                  ),
                ),
              ],
            )
          else
            _QuickAction(
              icon: Icons.fact_check_outlined,
              label: 'Go to attendance',
              onTap: onOpenAttendance,
            ),
          const SizedBox(height: 22),
          _SectionHeading(
            title: isLecturer ? 'Courses you teach' : 'My courses',
            trailing: isLecturer ? 'This semester' : null,
          ),
          const SizedBox(height: 10),
          ...state.courses
              .take(4)
              .map(
                (course) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _CourseTile(
                    course: course,
                    rosterSize: context
                        .read<UniversityBloc>()
                        .state
                        .studentsFor(course.id)
                        .length,
                    presentCount: context
                        .read<UniversityBloc>()
                        .state
                        .presentFor(course.id),
                    studentView: !isLecturer,
                  ),
                ),
              ),
        ],
      );
    },
  );
}

class _AttendanceHero extends StatelessWidget {
  const _AttendanceHero({
    required this.role,
    required this.rate,
    required this.present,
    required this.total,
    required this.onOpenAttendance,
  });
  final UniversityRole role;
  final int rate;
  final int present;
  final int total;
  final VoidCallback onOpenAttendance;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF087E78), Color(0xFF11645F)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                role == UniversityRole.lecturer
                    ? 'Today’s attendance'
                    : 'My attendance today',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _Pill(
              label: 'DEMO',
              color: Colors.white.withValues(alpha: .17),
              textColor: Colors.white,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$rate%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                role == UniversityRole.lecturer
                    ? '$present checked in from $total students'
                    : present == 0
                    ? 'Not checked in yet'
                    : 'Checked in for today',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .82),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            value: rate / 100,
            minHeight: 7,
            backgroundColor: Colors.white.withValues(alpha: .2),
            valueColor: const AlwaysStoppedAnimation(Colors.white),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onOpenAttendance,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.teal,
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(
              role == UniversityRole.lecturer
                  ? 'Manage sessions'
                  : 'Check my attendance',
            ),
          ),
        ),
      ],
    ),
  );
}

class _CoursesPage extends StatelessWidget {
  const _CoursesPage({
    required this.role,
    required this.onAddCourse,
    required this.onAddStudent,
  });
  final UniversityRole role;
  final VoidCallback onAddCourse;
  final VoidCallback onAddStudent;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<UniversityBloc, UniversityState>(
        builder: (context, state) {
          final isLecturer = role == UniversityRole.lecturer;
          final ownStudent = state.students.isEmpty
              ? null
              : state.students.first;
          final courses = isLecturer
              ? state.courses
              : ownStudent == null
              ? const <Course>[]
              : state.courses
                    .where((course) => course.id == ownStudent.courseId)
                    .toList();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _PageTitle(
                      title: isLecturer ? 'Courses' : 'My courses',
                      subtitle: isLecturer
                          ? 'Manage course rosters and sessions'
                          : 'Your current semester courses',
                    ),
                  ),
                  if (isLecturer)
                    IconButton.filledTonal(
                      onPressed: onAddCourse,
                      icon: const Icon(Icons.add_rounded),
                      tooltip: 'Add course',
                    ),
                ],
              ),
              const SizedBox(height: 14),
              ...courses.map(
                (course) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CourseDetailCard(
                    course: course,
                    studentView: !isLecturer,
                  ),
                ),
              ),
              if (isLecturer)
                OutlinedButton.icon(
                  onPressed: onAddStudent,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Enroll a student'),
                ),
              const SizedBox(height: 18),
            ],
          );
        },
      );
}

class _CourseDetailCard extends StatelessWidget {
  const _CourseDetailCard({required this.course, required this.studentView});
  final Course course;
  final bool studentView;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<UniversityBloc, UniversityState>(
        builder: (context, state) {
          final roster = context.read<UniversityBloc>().state.studentsFor(
            course.id,
          );
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 43,
                        height: 43,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F3F1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.menu_book_rounded,
                          color: AppTheme.teal,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              course.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              course.schedule,
                              style: const TextStyle(
                                color: Color(0xFF7B888F),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 13),
                    child: Divider(height: 1),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline_rounded,
                        size: 17,
                        color: Color(0xFF71808A),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          course.lecturer,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        studentView ? 'Enrolled' : '${roster.length} students',
                        style: const TextStyle(
                          color: AppTheme.teal,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (!studentView && roster.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...roster
                        .take(4)
                        .map(
                          (student) => Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: const Color(0xFFF1F3F3),
                                  child: Text(
                                    student.name.characters.first,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.ink,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    student.name,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                Text(
                                  student.matricNumber,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF87939A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                  if (state.openSessionCourseId == course.id)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: _Pill(
                        label: 'Attendance session open',
                        color: Color(0xFFE9F3F1),
                        textColor: AppTheme.teal,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
}

class _AttendancePage extends StatelessWidget {
  const _AttendancePage({required this.role, this.onEnrollFace});
  final UniversityRole role;
  final void Function(String studentId)? onEnrollFace;

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<UniversityBloc, UniversityState>(
    builder: (context, state) {
      final bloc = context.read<UniversityBloc>();
      final isLecturer = role == UniversityRole.lecturer;
      final student = state.students.isEmpty ? null : state.students.first;
      final courses = isLecturer
          ? state.courses
          : student == null
          ? const <Course>[]
          : state.courses
                .where((course) => course.id == student.courseId)
                .toList();
      final visibleEntries = isLecturer
          ? state.entries
          : student == null
          ? const <AttendanceEntry>[]
          : state.entries
                .where((entry) => entry.studentId == student.id)
                .toList();

      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _PageTitle(
            title: isLecturer ? 'Attendance' : 'My attendance',
            subtitle: isLecturer
                ? 'Open course sessions and monitor check-ins'
                : 'Identity verification is required for attendance',
          ),
          const SizedBox(height: 18),
          if (isLecturer) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Course sessions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Open attendance for a lecture, then monitor student check-ins.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF78858C)),
                    ),
                    const SizedBox(height: 14),
                    ...courses.map(
                      (course) => _LecturerSessionRow(
                        course: course,
                        isOpen: state.openSessionCourseId == course.id,
                        onToggle: () =>
                            bloc.add(AttendanceSessionToggled(course.id)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            if (courses.isEmpty)
              const _EmptyCard(
                icon: Icons.menu_book_outlined,
                title: 'No courses yet',
                subtitle: 'Contact your university admin to enroll in courses.',
              )
            else
              ...courses.map((course) {
                final isOpen = state.openSessionCourseId == course.id;
                // For now, we show the enroll face button always.
                // In a future version, we could track enrollment status in Firestore.
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AttendanceStateCard(
                    courseName: course.name,
                    isOpen: isOpen,
                    hasEnrolledFace: false, // TODO: Track enrollment status
                    onEnrollFace: () => onEnrollFace?.call(student!.id),
                    onCheckIn: () => bloc.add(const StudentCheckInRequested()),
                  ),
                );
              }),
          ],
          _SectionHeading(
            title: isLecturer
                ? 'Recent student check-ins'
                : 'My recent check-ins',
            trailing: '${visibleEntries.length}',
          ),
          const SizedBox(height: 10),
          if (visibleEntries.isEmpty)
            _EmptyCard(
              icon: Icons.fact_check_outlined,
              title: 'No check-ins yet',
              subtitle: isLecturer
                  ? 'Open a course session to start taking attendance.'
                  : 'Your check-ins will appear here.',
            ),
          ...visibleEntries.reversed.map((entry) {
            final attendees = state.students
                .where((item) => item.id == entry.studentId)
                .toList();
            final attendee = attendees.isEmpty ? null : attendees.first;
            final matchingCourses = state.courses
                .where((item) => item.id == entry.courseId)
                .toList();
            final course = matchingCourses.isEmpty
                ? null
                : matchingCourses.first;
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFE9F3F1),
                    child: Text(
                      attendee == null || attendee.name.isEmpty
                          ? '?'
                          : attendee.name.characters.first,
                      style: const TextStyle(color: AppTheme.teal),
                    ),
                  ),
                  title: Text(
                    isLecturer
                        ? attendee?.name ?? 'Student'
                        : course?.name ?? 'Course',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    isLecturer
                        ? '${course?.name ?? 'Course'} · ${entry.source}'
                        : 'Check-in recorded for today',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text(
                    DateFormat.jm().format(entry.checkedAt),
                    style: const TextStyle(
                      color: Color(0xFF78858C),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      );
    },
  );
}

class _LecturerSessionRow extends StatelessWidget {
  const _LecturerSessionRow({
    required this.course,
    required this.isOpen,
    required this.onToggle,
  });
  final Course course;
  final bool isOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  course.schedule,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7F8B91),
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: onToggle,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(isOpen ? 'End session' : 'Open session'),
          ),
        ],
      ),
    ),
  );
}

class _ReportsPage extends StatelessWidget {
  const _ReportsPage({required this.role});
  final UniversityRole role;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<UniversityBloc, UniversityState>(
        builder: (context, state) {
          final isLecturer = role == UniversityRole.lecturer;
          final student = state.students.isEmpty ? null : state.students.first;
          final total = isLecturer
              ? state.students.length
              : (student == null ? 0 : 1);
          final present = isLecturer
              ? state.entries.length
              : student == null
              ? 0
              : state.entries
                    .where((entry) => entry.studentId == student.id)
                    .length;
          final percent = total == 0 ? 0 : (present * 100 / total).round();
          final courses = isLecturer
              ? state.courses
              : student == null
              ? const <Course>[]
              : state.courses
                    .where((course) => course.id == student.courseId)
                    .toList();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _PageTitle(
                title: isLecturer ? 'Reports' : 'My attendance record',
                subtitle: isLecturer
                    ? 'A quick view of attendance across your courses'
                    : 'Your attendance for the current semester',
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.ink,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLecturer ? 'TODAY · UNIVERSITY' : 'MY ATTENDANCE',
                      style: const TextStyle(
                        color: Color(0xFFB9C8CE),
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$percent%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        height: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isLecturer
                          ? '$present present from $total registered students'
                          : present == 0
                          ? 'No check-in recorded today'
                          : 'You checked in today',
                      style: const TextStyle(
                        color: Color(0xFFCFD9DC),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeading(title: isLecturer ? 'By course' : 'My course'),
              const SizedBox(height: 10),
              ...courses.map((course) {
                final count = context
                    .read<UniversityBloc>()
                    .state
                    .studentsFor(course.id)
                    .length;
                final here = context.read<UniversityBloc>().state.presentFor(
                  course.id,
                );
                final value = isLecturer
                    ? (count == 0 ? 0.0 : here / count)
                    : (here > 0 ? 1.0 : 0.0);
                final status = isLecturer
                    ? '$here / $count'
                    : here > 0
                    ? 'Present'
                    : 'No record';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  course.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                status,
                                style: const TextStyle(
                                  color: Color(0xFF78858C),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: value,
                              minHeight: 7,
                              backgroundColor: const Color(0xFFEDF1EF),
                              valueColor: const AlwaysStoppedAnimation(
                                AppTheme.teal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          );
        },
      );
}

class _StudentsPage extends StatelessWidget {
  const _StudentsPage();

  @override
  Widget build(BuildContext context) => BlocBuilder<UniversityBloc, UniversityState>(
        builder: (context, state) {
          final students = state.students;
          final courses = {for (final c in state.courses) c.id: c.name};

          // Group students by course
          final studentsByCourse = <String, List<UniversityStudent>>{};
          for (final student in students) {
            studentsByCourse.putIfAbsent(student.courseId, () => <UniversityStudent>[]).add(student);
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _PageTitle(
                title: 'All Students',
                subtitle: 'View students grouped by their enrolled courses',
              ),
              const SizedBox(height: 18),
              if (students.isEmpty)
                _EmptyCard(
                  icon: Icons.people_alt_outlined,
                  title: 'No students yet',
                  subtitle: 'Use "Enroll student" on the Overview page to add students.',
                )
              else ...[
                ...studentsByCourse.entries.map((entry) {
                  final courseName = courses[entry.key] ?? entry.key;
                  final courseStudents = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8F3F1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.menu_book_rounded,
                                    color: AppTheme.teal,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        courseName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                      Text(
                                        '${courseStudents.length} student(s)',
                                        style: const TextStyle(
                                          color: Color(0xFF7B888F),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...courseStudents.map<Widget>((UniversityStudent student) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: const Color(0xFFF1F3F3),
                                    child: Text(
                                      student.name.characters.first,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.ink,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          student.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          'Matric: ${student.matricNumber.isEmpty ? 'N/A' : student.matricNumber}',
                                          style: const TextStyle(
                                            color: Color(0xFF78858C),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (student.userId != null)
                                    const Icon(
                                      Icons.verified_user_rounded,
                                      color: AppTheme.teal,
                                      size: 18,
                                    )
                                  else
                                    const Icon(
                                      Icons.person_outline_rounded,
                                      color: Color(0xFF9AA8AC),
                                      size: 18,
                                    ),
                                ],
                              ),
                            )),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
              const SizedBox(height: 8),
            ],
          );
        },
      );
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({
    required this.course,
    required this.rosterSize,
    required this.presentCount,
    required this.studentView,
  });
  final Course course;
  final int rosterSize;
  final int presentCount;
  final bool studentView;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF0FA),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: Color(0xFF636BA9),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                Text(
                  '${course.lecturer} · ${course.schedule}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7C898F),
                  ),
                ),
              ],
            ),
          ),
          if (studentView)
            const _Pill(
              label: 'Enrolled',
              color: Color(0xFFE9F3F1),
              textColor: AppTheme.teal,
            )
          else
            _Pill(
              label: '$presentCount / $rosterSize',
              color: const Color(0xFFE9F3F1),
              textColor: AppTheme.teal,
            ),
        ],
      ),
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.trailing});
  final String title;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: AppTheme.ink,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      if (trailing != null)
        Text(
          trailing!,
          style: const TextStyle(color: Color(0xFF839097), fontSize: 12),
        ),
    ],
  );
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w800,
          color: AppTheme.ink,
          letterSpacing: -.6,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: const TextStyle(fontSize: 13, color: Color(0xFF78858C)),
      ),
    ],
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color tint;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 13, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: AppTheme.teal),
          ),
          const SizedBox(height: 11),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFF78858C)),
          ),
        ],
      ),
    ),
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFE9F3F1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.teal, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.ink,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: Color(0xFF98A4A7),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.textColor,
  });
  final String label;
  final Color color;
  final Color textColor;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: textColor,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF91A09F), size: 32),
          const SizedBox(height: 9),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF78858C), fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

Future<List<String>?> _textFields(
  BuildContext context, {
  required String title,
  required List<(String, String)> fields,
}) async {
  final controllers = fields.map((_) => TextEditingController()).toList();
  final result = await showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < fields.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: controllers[i],
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: fields[i].$1,
                    hintText: fields[i].$2,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            dialogContext,
            controllers.map((controller) => controller.text.trim()).toList(),
          ),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  for (final controller in controllers) {
    controller.dispose();
  }
  return result;
}

Future<List<String>?> _studentFields(
  BuildContext context,
  List<Course> courses,
) async {
  if (courses.isEmpty) return null;
  final name = TextEditingController();
  final matric = TextEditingController();
  var courseId = courses.first.id;
  final result = await showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Enroll a student'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Student name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: matric,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Matric number'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: courseId,
              decoration: const InputDecoration(labelText: 'Course'),
              items: courses
                  .map(
                    (course) => DropdownMenuItem(
                      value: course.id,
                      child: Text(course.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => courseId = value);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, [
              name.text.trim(),
              matric.text.trim(),
              courseId,
            ]),
            child: const Text('Enroll'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  matric.dispose();
  return result;
}

class _AttendanceStateCard extends StatelessWidget {
  const _AttendanceStateCard({
    required this.courseName,
    required this.isOpen,
    required this.hasEnrolledFace,
    required this.onEnrollFace,
    required this.onCheckIn,
  });

  final String courseName;
  final bool isOpen;
  final bool hasEnrolledFace;
  final VoidCallback onEnrollFace;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                courseName,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 16),
              if (!hasEnrolledFace) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFB74D)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.face_outlined, color: Color(0xFFE65100), size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Face not enrolled yet. Enroll your face first to enable attendance verification.',
                          style: TextStyle(
                            color: Color(0xFFE65100),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: onEnrollFace,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFFB74D),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Enroll Face'),
                      ),
                    ],
                  ),
                ),
              ] else if (!isOpen) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF81C784)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded, color: Color(0xFF2E7D32), size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'No open session. Your lecturer will open the session when class starts.',
                          style: TextStyle(
                            color: Color(0xFF2E7D32),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: onCheckIn,
                  icon: const Icon(Icons.fingerprint_rounded, size: 20),
                  label: const Text('Verify Face & Check In'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppTheme.teal,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This will launch iProov face verification to confirm your identity.',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
}
