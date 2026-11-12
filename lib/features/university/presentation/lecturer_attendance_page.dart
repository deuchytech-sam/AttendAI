import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html;

import 'university_bloc.dart';
import 'university_event.dart';
import 'university_state.dart';
import '../data/datasources/firestore_university_data_source.dart';
import '../../../app/theme/app_theme.dart';
import '../domain/entities/course.dart';

/// Lecturer attendance page with real-time session attendance,
/// semester summary, and CSV export capabilities.
class LecturerAttendancePage extends StatefulWidget {
  const LecturerAttendancePage({super.key});

  @override
  State<LecturerAttendancePage> createState() => _LecturerAttendancePageState();
}

class _LecturerAttendancePageState extends State<LecturerAttendancePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedCourseId;
  String? _selectedSessionId;
  DateTime _semesterStart = DateTime(DateTime.now().year, 1, 1);
  DateTime _semesterEnd = DateTime(DateTime.now().year, 12, 31);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UniversityBloc, UniversityState>(
      builder: (context, state) {
        final courses = state.courses.where((c) => c.lecturer.isNotEmpty).toList();
        final isLoading = state.isLoadingSessionAttendance || state.isLoadingSemesterSummary;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Attendance Management'),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Live Session'),
                Tab(text: 'Semester Summary'),
              ],
            ),
          ),
          body: Column(
            children: [
              if (courses.isNotEmpty) ...[
                _CourseSelector(
                  courses: courses,
                  selectedCourseId: _selectedCourseId,
                  onChanged: (courseId) {
                    setState(() {
                      _selectedCourseId = courseId;
                      _selectedSessionId = null;
                    });
                    if (courseId != null) {
                      _loadOpenSession(context, courseId);
                    }
                  },
                ),
              ],
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _LiveSessionTab(
                      courseId: _selectedCourseId,
                      sessionId: _selectedSessionId,
                      state: state,
                      onExportCsv: _exportSessionCsv,
                      isLoading: isLoading,
                    ),
                    _SemesterSummaryTab(
                      courseId: _selectedCourseId,
                      semesterStart: _semesterStart,
                      semesterEnd: _semesterEnd,
                      state: state,
                      onDateRangeChanged: (start, end) {
                        setState(() {
                          _semesterStart = start;
                          _semesterEnd = end;
                        });
                        _loadSemesterSummary(context);
                      },
                      onExportCsv: _exportSemesterCsv,
                      isLoading: isLoading,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _loadOpenSession(BuildContext context, String courseId) {
    context.read<UniversityBloc>().add(
      SessionAttendanceRequested('', courseId: courseId),
    );
  }

  void _loadSemesterSummary(BuildContext context) {
    if (_selectedCourseId == null) return;
    context.read<UniversityBloc>().add(SemesterAttendanceSummaryRequested(
          courseId: _selectedCourseId!,
          semesterStart: _semesterStart,
          semesterEnd: _semesterEnd,
        ));
  }

  void _exportSessionCsv(SessionAttendance attendance) {
    final csv = _generateSessionCsv(attendance);
    _downloadCsv(csv, 'session_${attendance.sessionId}_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');
  }

  void _exportSemesterCsv(SemesterAttendanceSummary summary) {
    final csv = _generateSemesterCsv(summary);
    _downloadCsv(csv, 'semester_${summary.courseId}_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');
  }

  String _generateSessionCsv(SessionAttendance attendance) {
    final buffer = StringBuffer();
    buffer.writeln('Session ID,Course ID,Status,Opened At,Closed At,Total Students,Present,Absent,Attendance %');
    buffer.write('${attendance.sessionId},${attendance.courseId},${attendance.status},');
    buffer.write('${attendance.openedAt?.toIso8601String() ?? ''},');
    buffer.write('${attendance.closedAt?.toIso8601String() ?? ''},');
    buffer.write('${attendance.totalStudents},${attendance.presentCount},${attendance.absentCount},');
    buffer.write('${attendance.attendancePercentage.toStringAsFixed(1)}');
    buffer.writeln();

    buffer.writeln();
    buffer.writeln('Student ID,Student Name,Matric Number,Status,Checked At,Face Match Score,Provider');
    for (final student in attendance.attendance) {
      buffer.write('${student.studentId},${student.studentName},${student.matricNumber},');
      buffer.write('${student.status},');
      buffer.write('${student.checkedAt?.toIso8601String() ?? ''},');
      buffer.write('${student.faceMatchScore?.toStringAsFixed(4) ?? ''},');
      buffer.write('${student.verificationProvider ?? ''}');
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _generateSemesterCsv(SemesterAttendanceSummary summary) {
    final buffer = StringBuffer();
    buffer.writeln('Course ID,Semester Start,Semester End,Total Sessions');
    buffer.writeln('${summary.courseId},${summary.semesterStart},${summary.semesterEnd},${summary.totalSessions}');
    buffer.writeln();
    buffer.writeln('Student ID,Student Name,Matric Number,Sessions Attended,Total Sessions,Percentage %,Recent Sessions');
    for (final student in summary.studentSummaries) {
      final recent = student.recentSessions.map((s) => '${s.sessionId}(${s.checkedAt})').join('; ');
      buffer.write('${student.studentId},${student.studentName},${student.matricNumber},');
      buffer.write('${student.sessionsAttended},${student.totalSessions},${student.percentage},');
      buffer.write('$recent');
      buffer.writeln();
    }
    return buffer.toString();
  }

  void _downloadCsv(String csv, String filename) {
    final blob = html.Blob([csv], 'text/csv');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}

class _CourseSelector extends StatelessWidget {
  const _CourseSelector({
    required this.courses,
    required this.selectedCourseId,
    required this.onChanged,
  });

  final List<Course> courses;
  final String? selectedCourseId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Course',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: selectedCourseId,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: courses.map((course) => DropdownMenuItem<String>(
              value: course.id,
              child: Text(course.name, overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: onChanged,
            hint: const Text('Choose a course...'),
          ),
        ],
      ),
    );
  }
}

class _LiveSessionTab extends StatelessWidget {
  const _LiveSessionTab({
    required this.courseId,
    required this.sessionId,
    required this.state,
    required this.onExportCsv,
    required this.isLoading,
  });

  final String? courseId;
  final String? sessionId;
  final UniversityState state;
  final void Function(SessionAttendance) onExportCsv;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (courseId == null) {
      return _EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'Select a course',
        message: 'Choose a course from the dropdown to view live attendance.',
      );
    }

    final attendance = state.currentSessionAttendance;
    if (attendance == null || attendance.sessionId.isEmpty) {
      return _LoadingOrEmpty(
        isLoading: isLoading,
        emptyIcon: Icons.fact_check_outlined,
        emptyTitle: 'No active session',
        emptyMessage: 'Open a session for this course to see live attendance.',
      );
    }

    if (attendance.attendance.isEmpty) {
      return _EmptyState(
        icon: Icons.people_alt_outlined,
        title: 'No students enrolled',
        message: 'Enroll students in this course to track attendance.',
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        // Stream automatically updates, but we can trigger a reload
        context.read<UniversityBloc>().add(SessionAttendanceRequested(attendance.sessionId));
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _SessionHeader(attendance: attendance, onExport: () => onExportCsv(attendance)),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Present (${attendance.presentCount})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          SliverList.separated(
            itemCount: attendance.attendance.where((a) => a.status == 'present').length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final presentStudents = attendance.attendance.where((a) => a.status == 'present').toList();
              final student = presentStudents[index];
              return _StudentAttendanceTile(student: student, isPresent: true);
            },
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                'Absent (${attendance.absentCount})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          SliverList.separated(
            itemCount: attendance.attendance.where((a) => a.status == 'absent').length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final absentStudents = attendance.attendance.where((a) => a.status == 'absent').toList();
              final student = absentStudents[index];
              return _StudentAttendanceTile(student: student, isPresent: false);
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

class _SemesterSummaryTab extends StatelessWidget {
  const _SemesterSummaryTab({
    required this.courseId,
    required this.semesterStart,
    required this.semesterEnd,
    required this.state,
    required this.onDateRangeChanged,
    required this.onExportCsv,
    required this.isLoading,
  });

  final String? courseId;
  final DateTime semesterStart;
  final DateTime semesterEnd;
  final UniversityState state;
  final void Function(DateTime, DateTime) onDateRangeChanged;
  final void Function(SemesterAttendanceSummary) onExportCsv;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (courseId == null) {
      return _EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'Select a course',
        message: 'Choose a course from the dropdown to view semester summary.',
      );
    }

    final summary = state.semesterAttendanceSummary;
    if (summary == null && !isLoading) {
      return _LoadingOrEmpty(
        isLoading: false,
        emptyIcon: Icons.bar_chart_outlined,
        emptyTitle: 'No data available',
        emptyMessage: 'Select a date range and load the semester summary.',
        actionLabel: 'Load Summary',
        onAction: () => onDateRangeChanged(semesterStart, semesterEnd),
      );
    }

    if (isLoading) {
      return _LoadingOrEmpty(isLoading: true);
    }

    if (summary!.studentSummaries.isEmpty) {
      return _EmptyState(
        icon: Icons.people_alt_outlined,
        title: 'No students enrolled',
        message: 'Enroll students in this course to see semester summary.',
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        onDateRangeChanged(semesterStart, semesterEnd);
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _SemesterHeader(
              summary: summary,
              semesterStart: semesterStart,
              semesterEnd: semesterEnd,
              onDateRangeChanged: onDateRangeChanged,
              onExport: () => onExportCsv(summary),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Student Attendance (${summary.studentSummaries.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          SliverList.separated(
            itemCount: summary.studentSummaries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final student = summary.studentSummaries[index];
              return _StudentSemesterTile(student: student);
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.attendance,
    required this.onExport,
  });

  final SessionAttendance attendance;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: attendance.status == 'open'
              ? [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)]
              : [const Color(0xFFF3E5F5), const Color(0xFFE1BEE7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: attendance.status == 'open'
              ? const Color(0xFF81C784)
              : const Color(0xFFCE93D8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                attendance.status == 'open'
                    ? Icons.radio_button_checked_rounded
                    : Icons.stop_circle_rounded,
                color: attendance.status == 'open'
                    ? Colors.green.shade800
                    : Colors.deepPurple.shade800,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attendance.status == 'open' ? 'Session Active' : 'Session Ended',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: attendance.status == 'open'
                            ? Colors.green.shade800
                            : Colors.deepPurple.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Opened: ${attendance.openedAt != null ? DateFormat('MMM d, y · h:mm a').format(attendance.openedAt!) : '—'}',
                      style: TextStyle(
                        color: attendance.status == 'open'
                            ? Colors.green.shade700
                            : Colors.deepPurple.shade700,
                      ),
                    ),
                    if (attendance.closedAt != null)
                      Text(
                        'Closed: ${DateFormat('MMM d, y · h:mm a').format(attendance.closedAt!)}',
                        style: TextStyle(
                          color: attendance.status == 'open'
                              ? Colors.green.shade700
                              : Colors.deepPurple.shade700,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  label: 'Total',
                  value: '${attendance.totalStudents}',
                  color: Colors.blueGrey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatBox(
                  label: 'Present',
                  value: '${attendance.presentCount}',
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatBox(
                  label: 'Absent',
                  value: '${attendance.absentCount}',
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatBox(
                  label: 'Rate',
                  value: '${attendance.attendancePercentage.toStringAsFixed(1)}%',
                  color: AppTheme.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Export CSV'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SemesterHeader extends StatelessWidget {
  const _SemesterHeader({
    required this.summary,
    required this.semesterStart,
    required this.semesterEnd,
    required this.onDateRangeChanged,
    required this.onExport,
  });

  final SemesterAttendanceSummary summary;
  final DateTime semesterStart;
  final DateTime semesterEnd;
  final void Function(DateTime, DateTime) onDateRangeChanged;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded, color: Color(0xFF1565C0), size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Semester Attendance Summary',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total Sessions: ${summary.totalSessions}',
                      style: const TextStyle(color: Color(0xFF1E88E5)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _DatePickerField(
                  label: 'Semester Start',
                  date: semesterStart,
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: semesterStart,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (date != null && context.mounted) {
                      onDateRangeChanged(date, semesterEnd);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DatePickerField(
                  label: 'Semester End',
                  date: semesterEnd,
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: semesterEnd,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (date != null && context.mounted) {
                      onDateRangeChanged(semesterStart, date);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Export CSV'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF1E88E5)),
                const SizedBox(width: 8),
                Text(
                  DateFormat('MMM d, yyyy').format(date),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StudentAttendanceTile extends StatelessWidget {
  const _StudentAttendanceTile({
    required this.student,
    required this.isPresent,
  });

  final StudentAttendance student;
  final bool isPresent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPresent
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isPresent
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPresent ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: isPresent ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.studentName,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  'Matric: ${student.matricNumber}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (student.checkedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Checked in: ${DateFormat('HH:mm:ss').format(student.checkedAt!)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),
          ),
          if (student.faceMatchScore != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${(student.faceMatchScore! * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: student.faceMatchScore! >= 0.8 ? Colors.green : Colors.orange,
                  ),
                ),
                Text(
                  student.verificationProvider ?? 'face',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StudentSemesterTile extends StatelessWidget {
  const _StudentSemesterTile({required this.student});

  final StudentSemesterSummary student;

  @override
  Widget build(BuildContext context) {
    final percentageColor = student.percentage >= 75
        ? Colors.green
        : student.percentage >= 50
            ? Colors.orange
            : Colors.red;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
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
            child: const Icon(Icons.person_rounded, color: AppTheme.teal),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.studentName,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  'Matric: ${student.matricNumber}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '${student.sessionsAttended}/${student.totalSessions} sessions',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: percentageColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${student.percentage}%',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: percentageColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (student.recentSessions.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Last: ${student.recentSessions.first.checkedAt}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                if (student.recentSessions.first.faceMatchScore != null)
                  Text(
                    'Match: ${(student.recentSessions.first.faceMatchScore! * 100).toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
              ],
            ),
        ],
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
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
      ),
    );
  }
}

class _LoadingOrEmpty extends StatelessWidget {
  const _LoadingOrEmpty({
    required this.isLoading,
    this.emptyIcon,
    this.emptyTitle,
    this.emptyMessage,
    this.actionLabel,
    this.onAction,
  });

  final bool isLoading;
  final IconData? emptyIcon;
  final String? emptyTitle;
  final String? emptyMessage;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return _EmptyState(
      icon: emptyIcon ?? Icons.inbox_outlined,
      title: emptyTitle ?? 'No data',
      message: emptyMessage ?? 'No information available.',
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}