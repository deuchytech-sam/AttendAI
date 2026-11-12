import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../notifications/notification_service.dart';
import '../domain/entities/course.dart';
import '../domain/entities/university_role.dart';
import '../domain/entities/university_student.dart';
import 'university_bloc.dart';
import 'university_event.dart';
import 'university_state.dart';
import 'face_verification_screen.dart';
import 'face_enrollment_screen.dart';
import 'lecturer_attendance_page.dart';
import '../data/datasources/firestore_university_data_source.dart';

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

  String get fcc_universityId => widget.universityId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<UniversityBloc>().add(
          const UniversityDashboardRequested(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLecturer = _role == UniversityRole.lecturer;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.teal,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.fact_check_rounded,
                color: Colors.white,
                size: 22,
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
                    letterSpacing: -0.4,
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
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account options',
            onSelected: (value) {
              if (value == 'sign_out') {
                widget.onSignOut();
              } else if (value == 'profile') {
                _notice('${widget.displayName} · ${_role.name}');
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.person_outline_rounded),
                  title: Text('My profile'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'sign_out',
                child: ListTile(
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Sign out'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 16, left: 4),
              child: CircleAvatar(
                backgroundColor: const Color(0xFFDCEFEB),
                foregroundColor: AppTheme.teal,
                child: Text(
                  _initials(widget.displayName),
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
                message != null &&
                message.trim().isNotEmpty) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(message)));
            }

            // Initialize FCM notifications when dashboard is loaded
            if (state.status == UniversityLoadStatus.loaded) {
              _initializeNotifications(context, state);
            }
          },
          builder: (context, state) {
            if (state.status == UniversityLoadStatus.initial ||
                state.status == UniversityLoadStatus.loading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state.status == UniversityLoadStatus.failure) {
              return _ErrorState(
                message:
                    state.errorMessage ??
                    'Could not load the university dashboard.',
                onRetry: () {
                  context.read<UniversityBloc>().add(
                    const UniversityDashboardRequested(),
                  );
                },
              );
            }

            final openSessionCourse = state.openSessionCourseId == null
                ? null
                : state.courses.where((course) {
                    return course.id == state.openSessionCourseId;
                  }).firstOrNull;

            // Check if student has already checked in for the current session
            bool hasCheckedIn = false;
            DateTime? checkedInTime;
            if (!isLecturer &&
                openSessionCourse != null &&
                widget.matricNumber != null) {
              // Find the student record for this user
              final student = state.students
                  .where((s) => s.matricNumber == widget.matricNumber)
                  .firstOrNull;
              if (student != null) {
                // Find attendance entry for this student in the current session
                final entry = state.entries
                    .where(
                      (e) =>
                          e.studentId == student.id &&
                          e.courseId == openSessionCourse.id &&
                          e.sessionId == state.openSessionId,
                    )
                    .firstOrNull;
                if (entry != null) {
                  hasCheckedIn = true;
                  checkedInTime = entry.checkedAt;
                }
              }
            }

            return Column(
              children: [
                if (openSessionCourse != null ||
                    _shouldShowSessionBanner(state))
                  _SessionNotificationBanner(
                    course: openSessionCourse,
                    message: state.actionMessage,
                    onDismiss: () => _dismissActionMessage(context),
                    onCheckIn: !isLecturer && !hasCheckedIn
                        ? () => _startFaceVerification(context)
                        : null,
                    hasCheckedIn: hasCheckedIn,
                    checkedInTime: checkedInTime,
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      _OverviewPage(
                        role: _role,
                        displayName: widget.displayName,
                        matricNumber: widget.matricNumber,
                        onOpenAttendance: () => setState(() => _tab = 2),
                      ),
                      _CoursesPage(role: _role),
                      _AttendancePage(
                        role: _role,
                        universityId: widget.universityId,
                        matricNumber: widget.matricNumber,
                      ),
                      _ReportsPage(role: _role),
                      if (isLecturer) const LecturerAttendancePage(),
                      if (isLecturer) const _StudentsPage(),
                    ],
                  ),
                ),
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
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Overview',
          ),
          const NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Courses',
          ),
          const NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check_rounded),
            label: 'Attendance',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Reports',
          ),
          if (isLecturer)
            const NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check_rounded),
              label: 'Lecturer',
            ),
          if (isLecturer)
            const NavigationDestination(
              icon: Icon(Icons.people_alt_outlined),
              selectedIcon: Icon(Icons.people_alt_rounded),
              label: 'Students',
            ),
        ],
      ),
    );
  }

  bool _shouldShowSessionBanner(UniversityState state) {
    final message = state.actionMessage ?? '';
    return message.contains('Session started') ||
        message.contains('Session ended');
  }

  void _dismissActionMessage(BuildContext context) {
    context.read<UniversityBloc>().add(const ActionMessageDismissed());
  }

  void _initializeNotifications(BuildContext context, UniversityState state) {
    final bloc = context.read<UniversityBloc>();
    final userId = bloc.dataSource.userId;
    final universityId = widget.universityId;

    // Get enrolled course IDs from state.courses
    final enrolledCourseIds = state.courses.map((c) => c.id).toList();

    NotificationService().initialize(
      userId: userId,
      universityId: universityId,
      enrolledCourseIds: enrolledCourseIds,
    );
  }

  Future<void> _startFaceVerification(BuildContext context) async {
    final bloc = context.read<UniversityBloc>();
    final userId = bloc.dataSource.userId;
    final universityId = widget.universityId;
    final livenessService = bloc.dataSource.livenessService;
    final dataSource = bloc.dataSource;

    final universityBloc = context.read<UniversityBloc>();

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: universityBloc,
          child: FaceVerificationScreen(
            userId: userId,
            universityId: universityId,
            livenessService: livenessService,
            dataSource: dataSource,
          ),
        ),
      ),
    );

    if (result == true && context.mounted) {
      final bloc = context.read<UniversityBloc>();
      bloc.add(const UniversityDashboardRequested());
      if (_role == UniversityRole.student) {
        final now = DateTime.now();
        bloc.add(
          StudentAttendanceHistoryRequested(
            courseId: bloc.state.openSessionCourseId,
            semesterStart: DateTime(now.year, 1, 1),
            semesterEnd: DateTime(now.year, 12, 31),
          ),
        );
      }
      _notice('Check-in recorded successfully!');
    }
  }

  void _notice(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

String _initials(String name) {
  return name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();
}

class _SessionNotificationBanner extends StatelessWidget {
  const _SessionNotificationBanner({
    required this.course,
    required this.message,
    required this.onDismiss,
    required this.hasCheckedIn,
    required this.checkedInTime,
    this.onCheckIn,
  });

  final Course? course;
  final String? message;
  final VoidCallback onDismiss;
  final VoidCallback? onCheckIn;
  final bool hasCheckedIn;
  final DateTime? checkedInTime;

  @override
  Widget build(BuildContext context) {
    final isOpen = course != null;
    final courseName = course?.name ?? 'this course';
    final msg = message ?? '';
    final foreground = isOpen
        ? const Color(0xFF1B5E20)
        : const Color(0xFF4A148C);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isOpen
              ? [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)]
              : [const Color(0xFFF3E5F5), const Color(0xFFE1BEE7)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOpen ? const Color(0xFF81C784) : const Color(0xFFCE93D8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOpen
                    ? Icons.play_circle_filled_rounded
                    : Icons.stop_circle_rounded,
                color: foreground,
                size: 25,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOpen ? 'Session started' : 'Session ended',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      msg.isNotEmpty
                          ? msg
                          : isOpen
                          ? 'Attendance is open for $courseName.'
                          : 'The attendance session has ended.',
                      style: TextStyle(
                        fontSize: 12,
                        color: foreground.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                tooltip: 'Dismiss notification',
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
          if (isOpen && hasCheckedIn) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: foreground, size: 20),
                const SizedBox(width: 8),
                Text(
                  checkedInTime == null
                      ? 'You have checked in.'
                      : 'Checked in at ${DateFormat('HH:mm:ss').format(checkedInTime!)}',
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ] else if (isOpen && onCheckIn != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCheckIn,
                icon: const Icon(Icons.face_rounded),
                label: const Text('Verify face and check in'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.teal,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({
    required this.role,
    required this.displayName,
    required this.onOpenAttendance,
    this.matricNumber,
  });

  final UniversityRole role;
  final String displayName;
  final VoidCallback onOpenAttendance;
  final String? matricNumber;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UniversityBloc, UniversityState>(
      builder: (context, state) {
        final courses = state.courses;
        final isLecturer = role == UniversityRole.lecturer;
        final hasOpenSession = state.openSessionCourseId != null;

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Welcome back,',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              displayName,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              isLecturer
                  ? 'Manage your courses and attendance.'
                  : 'Stay on top of your classes and attendance.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            if (matricNumber != null && matricNumber!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Matric number: $matricNumber',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF087F8C), Color(0xFF0B5968)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.fact_check_rounded,
                    color: Colors.white70,
                    size: 32,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    isLecturer
                        ? 'Your teaching dashboard'
                        : 'Your attendance dashboard',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasOpenSession
                        ? 'An attendance session is currently open.'
                        : 'Manage university activity from one place.',
                    style: const TextStyle(color: Colors.white70, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onOpenAttendance,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Open attendance'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF087F8C),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            const _SectionHeading(title: 'At a glance'),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [
                _DashboardMetric(
                  title: 'Courses',
                  value: '${courses.length}',
                  icon: Icons.menu_book_rounded,
                  color: AppTheme.teal,
                ),
                _DashboardMetric(
                  title: 'Open sessions',
                  value: hasOpenSession ? '1' : '0',
                  icon: Icons.radio_button_checked_rounded,
                  color: hasOpenSession ? Colors.green : Colors.blueGrey,
                ),
                _DashboardMetric(
                  title: 'Your role',
                  value: isLecturer ? 'Lecturer' : 'Student',
                  icon: Icons.person_outline_rounded,
                  color: Colors.deepPurple,
                ),
                _DashboardMetric(
                  title: 'Session status',
                  value: hasOpenSession ? 'Active' : 'Inactive',
                  icon: Icons.fact_check_outlined,
                  color: hasOpenSession ? Colors.green : Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 26),
            const _SectionHeading(title: 'Quick actions'),
            const SizedBox(height: 12),
            _ActionTile(
              icon: Icons.fact_check_outlined,
              title: 'Attendance',
              subtitle: 'View current attendance session information.',
              onTap: onOpenAttendance,
            ),
            const SizedBox(height: 26),
            const _SectionHeading(title: 'Your courses'),
            const SizedBox(height: 12),
            if (courses.isEmpty)
              _EmptyState(
                icon: Icons.menu_book_outlined,
                title: 'No courses yet',
                message: isLecturer
                    ? 'Courses assigned by your school admin will appear here.'
                    : 'Your assigned courses will appear here.',
              )
            else
              ...courses
                  .take(4)
                  .map(
                    (course) => _CourseCard(
                      course: course,
                      isOpen: course.id == state.openSessionCourseId,
                      isLecturer: isLecturer,
                      onToggleSession: isLecturer
                          ? () => context.read<UniversityBloc>().add(
                              AttendanceSessionToggled(course.id),
                            )
                          : null,
                    ),
                  ),
          ],
        );
      },
    );
  }
}

class _CoursesPage extends StatelessWidget {
  const _CoursesPage({required this.role});

  final UniversityRole role;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UniversityBloc, UniversityState>(
      builder: (context, state) {
        final courses = state.courses;
        final isLecturer = role == UniversityRole.lecturer;

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Courses',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${courses.length} course${courses.length == 1 ? '' : 's'} available',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            if (courses.isEmpty)
              _EmptyState(
                icon: Icons.menu_book_outlined,
                title: 'No courses available',
                message: isLecturer
                    ? 'Courses assigned by your school admin will appear here.'
                    : 'Your assigned courses will appear here.',
              )
            else
              ...courses.map(
                (course) => _CourseCard(
                  course: course,
                  isOpen: course.id == state.openSessionCourseId,
                  isLecturer: isLecturer,
                  onToggleSession: isLecturer
                      ? () => context.read<UniversityBloc>().add(
                          AttendanceSessionToggled(course.id),
                        )
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AttendancePage extends StatelessWidget {
  const _AttendancePage({
    required this.role,
    required this.universityId,
    this.matricNumber,
  });

  final UniversityRole role;
  final String universityId;
  final String? matricNumber;

  Future<void> _requestEnrollment(BuildContext context) async {
    final state = context.read<UniversityBloc>().state;
    final students = state.students
        .where((s) => s.userId != null && s.userId!.isNotEmpty)
        .toList();

    if (students.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No students with linked Firebase accounts found. Students must sign in first to link their account.',
            ),
          ),
        );
      }
      return;
    }

    final selectedStudent = await showDialog<UniversityStudent>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Select student to enroll'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: students.length,
            itemBuilder: (_, index) {
              final student = students[index];
              return ListTile(
                title: Text(student.name),
                subtitle: Text('Matric: ${student.matricNumber}'),
                onTap: () => Navigator.pop(dialogContext, student),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedStudent == null || !context.mounted) return;

    // Use the student's Firebase Auth UID (userId) for enrollment
    final faceEnrollmentId = selectedStudent.userId!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.face_retouching_natural_rounded,
          size: 38,
          color: AppTheme.teal,
        ),
        title: Text('Enroll face for ${selectedStudent.name}'),
        content: const Text(
          'This will start the camera to capture the student\'s face '
          'and create a biometric profile for attendance. '
          'The student should be present and positioned in front of the camera.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // Get the liveness service and data source from the bloc
    final bloc = context.read<UniversityBloc>();
    final livenessService = bloc.dataSource.livenessService;
    final dataSource = bloc.dataSource;

    // Launch the enrollment screen
    final enrolled = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FaceEnrollmentScreen(
          userId: faceEnrollmentId,
          universityId: universityId,
          livenessService: livenessService,
          dataSource: dataSource,
        ),
      ),
    );

    if (!context.mounted) return;

    if (enrolled == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Face enrolled successfully for ${selectedStudent.name}.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Face enrollment was cancelled or failed.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLecturer = role == UniversityRole.lecturer;

    return BlocBuilder<UniversityBloc, UniversityState>(
      builder: (context, state) {
        final openCourse = state.openSessionCourseId == null
            ? null
            : state.courses
                  .where((course) => course.id == state.openSessionCourseId)
                  .firstOrNull;

        // For students, find their student record to check attendance status
        UniversityStudent? currentStudent;
        if (!isLecturer && matricNumber != null) {
          currentStudent = state.students
              .where((s) => s.matricNumber == matricNumber)
              .firstOrNull;
        }

        // Check if student has checked in for the current session
        bool hasCheckedIn = false;
        DateTime? checkedInTime;
        final openCourseId = openCourse?.id;
        final currentStudentId = currentStudent?.id;
        if (!isLecturer && openCourseId != null && currentStudentId != null) {
          final entry = state.entries
              .where(
                (e) =>
                    e.studentId == currentStudentId &&
                    e.courseId == openCourseId &&
                    e.sessionId == state.openSessionId,
              )
              .firstOrNull;
          if (entry != null) {
            hasCheckedIn = true;
            checkedInTime = entry.checkedAt;
          }
        }

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Attendance',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Attendance sessions and face verification.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: openCourse != null
                    ? const Color(0xFFE5F5EE)
                    : const Color(0xFFF1F4F6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: openCourse != null
                      ? const Color(0xFF9BD6BB)
                      : const Color(0xFFDDE4E8),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    openCourse != null
                        ? Icons.radio_button_checked_rounded
                        : Icons.event_available_outlined,
                    size: 34,
                    color: openCourse != null
                        ? Colors.green.shade800
                        : Colors.blueGrey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    openCourse != null
                        ? 'Attendance session active'
                        : 'No active session',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    openCourse != null
                        ? 'An attendance session is open for ${openCourse.name}.'
                        : 'When a lecturer opens a session, its status will appear here.',
                    style: TextStyle(color: Colors.grey.shade700, height: 1.5),
                  ),
                  if (!isLecturer && openCourse != null && hasCheckedIn) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: Colors.green.shade700,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Checked in',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: Colors.green.shade800,
                                  ),
                                ),
                                if (checkedInTime != null)
                                  Text(
                                    'At ${DateFormat('HH:mm:ss').format(checkedInTime!)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            const _SectionHeading(title: 'Face verification'),
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.face_retouching_natural_rounded,
              title: 'Biometric enrollment',
              message: isLecturer
                  ? 'Start face enrollment for a student using their Firebase UID.'
                  : 'Face verification is available through the configured biometric service.',
            ),
            if (isLecturer) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _requestEnrollment(context),
                  icon: const Icon(Icons.face_rounded),
                  label: const Text('Enroll student face'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.teal,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            const _SectionHeading(title: 'Course sessions'),
            const SizedBox(height: 12),
            if (state.courses.isEmpty)
              const _EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'No courses found',
                message: 'Course sessions will appear here when courses are available.',
              )
            else
              ...state.courses.map(
                (course) => _CourseCard(
                  course: course,
                  isOpen: course.id == state.openSessionCourseId,
                  isLecturer: isLecturer,
                  onToggleSession: isLecturer
                      ? () => context.read<UniversityBloc>().add(
                          AttendanceSessionToggled(course.id),
                        )
                      : null,
                ),
              ),
            // Student attendance history
            if (!isLecturer) ...[
              const SizedBox(height: 24),
              _StudentAttendanceHistorySection(
                state: state,
                matricNumber: matricNumber,
                universityId: universityId,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ReportsPage extends StatelessWidget {
  const _ReportsPage({required this.role});

  final UniversityRole role;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UniversityBloc, UniversityState>(
      builder: (context, state) {
        final courses = state.courses;
        final openSessions = state.openSessionCourseId == null ? 0 : 1;
        final isLecturer = role == UniversityRole.lecturer;

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Reports',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Review the university information currently available.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [
                _DashboardMetric(
                  title: 'Total courses',
                  value: '${courses.length}',
                  icon: Icons.menu_book_rounded,
                  color: AppTheme.teal,
                ),
                _DashboardMetric(
                  title: 'Open sessions',
                  value: '$openSessions',
                  icon: Icons.fact_check_outlined,
                  color: Colors.green.shade700,
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _SectionHeading(title: 'Course overview'),
            const SizedBox(height: 12),
            if (courses.isEmpty)
              const _EmptyState(
                icon: Icons.bar_chart_rounded,
                title: 'No report data yet',
                message: 'Course information will appear here when available.',
              )
            else
              ...courses.map(
                (course) => _CourseCard(
                  course: course,
                  isOpen: course.id == state.openSessionCourseId,
                  isLecturer: isLecturer,
                  onToggleSession: isLecturer
                      ? () => context.read<UniversityBloc>().add(
                          AttendanceSessionToggled(course.id),
                        )
                      : null,
                ),
              ),
            const SizedBox(height: 16),
            const _InfoCard(
              icon: Icons.insights_rounded,
              title: 'Detailed attendance analytics',
              message: 'Attendance percentages, historical session records, and downloadable reports require attendance records from the university data layer.',
            ),
          ],
        );
      },
    );
  }
}

class _StudentsPage extends StatelessWidget {
  const _StudentsPage();

  Future<void> _repairLink(
    BuildContext context,
    UniversityStudent student,
  ) async {
    try {
      final result = await context
          .read<UniversityBloc>()
          .dataSource
          .linkStudentRosterRecord(student.id);
      if (!context.mounted) return;
      context.read<UniversityBloc>().add(const UniversityDashboardRequested());
      final displayName = result['displayName'] as String? ?? student.name;
      final email = result['email'] as String? ?? '';
      final message = email.isEmpty
          ? 'Linked ' +
                student.name +
                ' to the account for ' +
                displayName +
                '.'
          : 'Linked ' +
                student.name +
                ' to ' +
                displayName +
                ' (' +
                email +
                ').';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } on FirebaseFunctionsException catch (error, stackTrace) {
      debugPrint(
        '[StudentLinkRepair] code=' +
            error.code +
            ', message=' +
            (error.message ?? '') +
            ', details=' +
            (error.details?.toString() ?? '') +
            '\n' +
            stackTrace.toString(),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              error.message ?? 'Could not repair this student link.',
            ),
          ),
        );
    } catch (error, stackTrace) {
      debugPrint(
        '[StudentLinkRepair] ' +
            error.toString() +
            '\n' +
            stackTrace.toString(),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Could not repair this student link. Please try again.',
            ),
          ),
        );
    }
  }

  Future<void> _resetFaceEnrollment(
    BuildContext context,
    UniversityStudent student,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.face_retouching_off_rounded),
        title: const Text('Reset face enrollment?'),
        content: Text(
          'This will remove ${student.name}\'s current face template. '
          'They will need to enroll again before checking in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset face'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context
          .read<UniversityBloc>()
          .dataSource
          .resetStudentFaceEnrollment(student.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${student.name}\'s face was reset. They can enroll again now.',
            ),
          ),
        );
    } on FirebaseFunctionsException catch (error, stackTrace) {
      debugPrint(
        '[FaceEnrollmentReset] code=${error.code}, message=${error.message}, '
        'details=${error.details}\n$stackTrace',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Could not reset face enrollment.'),
          ),
        );
    } catch (error, stackTrace) {
      debugPrint('[FaceEnrollmentReset] $error\n$stackTrace');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not reset face enrollment. Please try again.'),
          ),
        );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<UniversityBloc, UniversityState>(
    builder: (context, state) {
      final students = [...state.students]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Students',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Review course enrollment and repair student account links.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          if (students.isEmpty)
            const _EmptyState(
              icon: Icons.people_alt_outlined,
              title: 'No students enrolled',
              message: 'Enroll a student from the Courses page first.',
            )
          else
            ...students.map((student) {
              final course = state.courses
                  .where((item) => item.id == student.courseId)
                  .firstOrNull;
              final accountStatus = student.userId == null
                  ? 'Account not linked'
                  : 'Account linked';
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(child: Text(_initials(student.name))),
                  title: Text(student.name),
                  subtitle: Text(
                    student.matricNumber +
                        ' � ' +
                        (course?.name ?? student.courseId) +
                        '\n' +
                        accountStatus,
                  ),
                  isThreeLine: true,
                  trailing: Wrap(
                    spacing: 2,
                    children: [
                      IconButton(
                        tooltip: 'Repair account link',
                        onPressed: () => _repairLink(context, student),
                        icon: Icon(
                          student.userId == null
                              ? Icons.link_rounded
                              : Icons.manage_accounts_outlined,
                        ),
                      ),
                      if (student.userId != null && student.userId!.isNotEmpty)
                        IconButton(
                          tooltip: 'Reset face enrollment',
                          onPressed: () =>
                              _resetFaceEnrollment(context, student),
                          icon: const Icon(Icons.face_retouching_off_rounded),
                        ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 16),
          const _InfoCard(
            icon: Icons.face_retouching_natural_rounded,
            title: 'Face enrollment',
            message: 'Use the Attendance page to start biometric enrollment for an existing student.',
          ),
        ],
      );
    },
  );
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.course,
    required this.isOpen,
    this.onToggleSession,
    this.isLecturer = false,
  });

  final Course course;
  final bool isOpen;
  final VoidCallback? onToggleSession;
  final bool isLecturer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOpen
              ? AppTheme.teal.withValues(alpha: 0.6)
              : Colors.grey.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.teal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.menu_book_rounded, color: AppTheme.teal),
          ),
          const SizedBox(width: 14),
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
                const SizedBox(height: 6),
                Text(
                  isOpen ? 'Attendance session active' : 'Course',
                  style: TextStyle(
                    color: isOpen ? AppTheme.teal : Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: isOpen ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          if (isLecturer && onToggleSession != null) ...[
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onToggleSession,
              icon: Icon(
                isOpen
                    ? Icons.stop_circle_rounded
                    : Icons.play_circle_fill_rounded,
                size: 18,
              ),
              label: Text(isOpen ? 'Close session' : 'Open session'),
              style: FilledButton.styleFrom(
                backgroundColor: isOpen ? Colors.red.shade600 : AppTheme.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ] else if (isOpen)
            const Icon(Icons.radio_button_checked_rounded, color: AppTheme.teal)
          else
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.teal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: AppTheme.teal),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.5),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.teal, size: 27),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 7),
                Text(
                  message,
                  style: TextStyle(color: Colors.grey.shade600, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentAttendanceHistorySection extends StatelessWidget {
  const _StudentAttendanceHistorySection({
    required this.state,
    required this.matricNumber,
    required this.universityId,
  });

  final UniversityState state;
  final String? matricNumber;
  final String universityId;

  @override
  Widget build(BuildContext context) {
    if (matricNumber == null || matricNumber!.isEmpty) {
      return const _EmptyState(
        icon: Icons.person_off_outlined,
        title: 'Matric number not set',
        message:
            'Your matriculation number is required to view attendance history.',
      );
    }

    final student = state.students
        .where((s) => s.matricNumber == matricNumber)
        .firstOrNull;

    if (student == null) {
      return const _EmptyState(
        icon: Icons.person_search_outlined,
        title: 'Student record not found',
        message:
            'Your student record could not be found. Contact your lecturer.',
      );
    }

    // Check if history is loading
    if (state.isLoadingStudentHistory) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final history = state.studentAttendanceHistory;

    if (history == null) {
      // Provide a button to load history
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(title: 'My Attendance History'),
          const SizedBox(height: 12),
          _EmptyState(
            icon: Icons.history_outlined,
            title: 'Attendance history not loaded',
            message:
                'Tap to load your attendance records for the current semester.',
            actionLabel: 'Load History',
            onAction: () {
              context.read<UniversityBloc>().add(
                StudentAttendanceHistoryRequested(
                  semesterStart: DateTime(DateTime.now().year, 1, 1),
                  semesterEnd: DateTime(DateTime.now().year, 12, 31),
                ),
              );
            },
          ),
        ],
      );
    }

    if (history.history.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(title: 'My Attendance History'),
          const SizedBox(height: 12),
          _EmptyState(
            icon: Icons.history_outlined,
            title: 'No attendance records',
            message:
                'Your attendance history for this semester will appear here.',
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'My Attendance History',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                context.read<UniversityBloc>().add(
                  StudentAttendanceHistoryRequested(
                    semesterStart: DateTime(DateTime.now().year, 1, 1),
                    semesterEnd: DateTime(DateTime.now().year, 12, 31),
                  ),
                );
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SemesterSummaryCard(history: history),
        const SizedBox(height: 16),
        ...history.history.map((entry) => _HistoryEntryTile(entry: entry)),
      ],
    );
  }
}

class _SemesterSummaryCard extends StatelessWidget {
  const _SemesterSummaryCard({required this.history});

  final StudentAttendanceHistory history;

  @override
  Widget build(BuildContext context) {
    final percentageColor = history.percentage >= 75
        ? Colors.green
        : history.percentage >= 50
        ? Colors.orange
        : Colors.red;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Semester Summary',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${history.courseId.isEmpty ? 'All Courses' : history.courseId}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${history.attendedCount}/${history.totalSessions}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: percentageColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${history.percentage}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: percentageColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: history.totalSessions > 0
                ? history.attendedCount / history.totalSessions
                : 0,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(percentageColor),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Text(
            'Semester: ${history.semesterStart} to ${history.semesterEnd}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class _HistoryEntryTile extends StatelessWidget {
  const _HistoryEntryTile({required this.entry});

  final StudentHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final statusColor = entry.checkedIn ? Colors.green : Colors.red;
    final statusIcon = entry.checkedIn
        ? Icons.check_circle_rounded
        : Icons.cancel_rounded;
    final statusText = entry.checkedIn ? 'Present' : 'Absent';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(statusIcon, color: statusColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.courseId,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.sessionDate} · ${entry.sessionStatus}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (entry.checkedIn && entry.checkedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Checked in: ${entry.checkedAt}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                statusText,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: statusColor,
                ),
              ),
              if (entry.faceMatchScore != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Match: ${(entry.faceMatchScore! * 100).toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 52,
              color: Colors.blueGrey,
            ),
            const SizedBox(height: 16),
            const Text(
              'Unable to load dashboard',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
