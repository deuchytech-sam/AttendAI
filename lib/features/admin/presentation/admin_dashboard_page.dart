import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/app_theme.dart';
import '../../university/domain/entities/course.dart';
import '../../university/domain/entities/university_role.dart';
import '../../auth/domain/entities/university_account.dart';
import '../../auth/presentation/auth_bloc.dart';
import '../../auth/presentation/auth_event.dart';
import '../domain/entities/admin_dashboard.dart';
import 'admin_bloc.dart';
import 'admin_event.dart';
import 'admin_state.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key, required this.account});

  final UniversityAccount account;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('University admin'),
      actions: [
        IconButton(
          tooltip: 'Refresh requests',
          onPressed: () =>
              context.read<AdminBloc>().add(const AdminDashboardRequested()),
          icon: const Icon(Icons.refresh_rounded),
        ),
        IconButton(
          tooltip: 'Sign out',
          onPressed: () =>
              context.read<AuthBloc>().add(const AuthSignOutRequested()),
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: BlocConsumer<AdminBloc, AdminState>(
        listener: (context, state) {
          final message = state.errorMessage ?? state.actionMessage;
          if (message != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(message)));
          }
        },
        builder: (context, state) {
          if (state.status == AdminLoadStatus.loading ||
              state.status == AdminLoadStatus.initial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status == AdminLoadStatus.failure) {
            return _LoadFailure(
              message:
                  state.errorMessage ?? 'Could not load approval requests.',
            );
          }
          final requests = state.dashboard.pendingAccounts;
          return RefreshIndicator(
            onRefresh: () async =>
                context.read<AdminBloc>().add(const AdminDashboardRequested()),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Text(
                  'Welcome, ${account.displayName}',
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Review account requests for ${account.universityId}.',
                  style: const TextStyle(color: Color(0xFF74848A)),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Pending accounts',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Chip(label: Text('${requests.length}')),
                  ],
                ),
                const SizedBox(height: 12),
                if (requests.isEmpty)
                  const _NoPendingAccounts()
                else
                  ...requests.map(
                    (request) => _PendingAccountCard(
                      account: request,
                      courses: state.dashboard.courses,
                      onApprove: (courseIds) => context.read<AdminBloc>().add(
                        AdminAccountApprovalRequested(
                          account: request,
                          courseIds: courseIds,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Courses',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _openCourseEditor(
                        context,
                        course: null,
                        lecturers: state.dashboard.lecturers,
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add course'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (state.dashboard.courses.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'No courses yet. Add a course and assign lecturers.',
                      ),
                    ),
                  )
                else
                  ...state.dashboard.courses.map((course) {
                    final lecturerNames = {
                      for (final lecturer in state.dashboard.lecturers)
                        lecturer.uid: lecturer.displayName,
                    };
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        title: Text(course.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              course.lecturerIds.isEmpty
                                  ? 'No lecturer assigned'
                                  : course.lecturerNames(lecturerNames),
                              style: TextStyle(
                                color: course.lecturerIds.isEmpty
                                    ? Colors.deepOrange.shade700
                                    : null,
                                fontWeight: course.lecturerIds.isEmpty
                                    ? FontWeight.w600
                                    : null,
                              ),
                            ),
                            if (course.lecturerIds.isEmpty &&
                                course.lecturer.trim().isNotEmpty &&
                                course.lecturer.toLowerCase() != 'unassigned')
                              Text('Legacy lecturer name: ${course.lecturer}'),
                            Text(course.schedule),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: 'Edit course and lecturer assignments',
                          onPressed: () => _openCourseEditor(
                            context,
                            course: course,
                            lecturers: state.dashboard.lecturers,
                          ),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _openCourseEditor(
  BuildContext context, {
  required Course? course,
  required List<UniversityAccount> lecturers,
}) async {
  final bloc = context.read<AdminBloc>();
  final result = await showDialog<_CourseFormValue>(
    context: context,
    builder: (_) => _CourseEditorDialog(course: course, lecturers: lecturers),
  );
  if (result == null || !context.mounted) return;
  bloc.add(
    AdminCourseSavedRequested(
      courseId: course?.id,
      name: result.name,
      schedule: result.schedule,
      lecturerIds: result.lecturerIds,
    ),
  );
}

class _CourseFormValue {
  const _CourseFormValue({
    required this.name,
    required this.schedule,
    required this.lecturerIds,
  });

  final String name;
  final String schedule;
  final List<String> lecturerIds;
}

class _CourseEditorDialog extends StatefulWidget {
  const _CourseEditorDialog({required this.course, required this.lecturers});

  final Course? course;
  final List<UniversityAccount> lecturers;

  @override
  State<_CourseEditorDialog> createState() => _CourseEditorDialogState();
}

class _CourseEditorDialogState extends State<_CourseEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _scheduleController;
  late final Set<String> _selectedLecturerIds;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.course?.name ?? '');
    _scheduleController = TextEditingController(
      text: widget.course?.schedule ?? '',
    );
    _selectedLecturerIds = {...?widget.course?.lecturerIds};
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scheduleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeIds = widget.lecturers.map((lecturer) => lecturer.uid).toSet();
    final inactiveIds = _selectedLecturerIds.difference(activeIds).toList()
      ..sort();
    return AlertDialog(
      title: Text(widget.course == null ? 'Add course' : 'Edit course'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Course name'),
                  validator: (value) => value?.trim().isEmpty == true
                      ? 'Enter a course name.'
                      : null,
                ),
                TextFormField(
                  controller: _scheduleController,
                  decoration: const InputDecoration(labelText: 'Schedule'),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Assigned lecturers',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const Text('Choose up to 8 lecturers.'),
                if (widget.lecturers.isEmpty && inactiveIds.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No active lecturers are available yet.'),
                  ),
                ...widget.lecturers.map(
                  (lecturer) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _selectedLecturerIds.contains(lecturer.uid),
                    title: Text(
                      lecturer.displayName.isEmpty
                          ? lecturer.email
                          : lecturer.displayName,
                    ),
                    subtitle: lecturer.email.isEmpty
                        ? null
                        : Text(lecturer.email),
                    onChanged:
                        !_selectedLecturerIds.contains(lecturer.uid) &&
                            _selectedLecturerIds.length >= 8
                        ? null
                        : (selected) => setState(() {
                            if (selected == true) {
                              _selectedLecturerIds.add(lecturer.uid);
                            } else {
                              _selectedLecturerIds.remove(lecturer.uid);
                            }
                          }),
                  ),
                ),
                ...inactiveIds.map(
                  (id) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _selectedLecturerIds.contains(id),
                    title: const Text('Inactive lecturer — remove to save'),
                    subtitle: Text(id),
                    onChanged:
                        !_selectedLecturerIds.contains(id) &&
                            _selectedLecturerIds.length >= 8
                        ? null
                        : (selected) => setState(() {
                            if (selected == true) {
                              _selectedLecturerIds.add(id);
                            } else {
                              _selectedLecturerIds.remove(id);
                            }
                          }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _CourseFormValue(
                name: _nameController.text.trim(),
                schedule: _scheduleController.text.trim(),
                lecturerIds: _selectedLecturerIds.toList(),
              ),
            );
          },
          child: Text(widget.course == null ? 'Create course' : 'Save changes'),
        ),
      ],
    );
  }
}

class _PendingAccountCard extends StatelessWidget {
  const _PendingAccountCard({
    required this.account,
    required this.courses,
    required this.onApprove,
  });

  final PendingAccount account;
  final List<Course> courses;
  final ValueChanged<List<String>> onApprove;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFE9F3F1),
                foregroundColor: AppTheme.teal,
                child: Text(
                  account.displayName.isEmpty
                      ? '?'
                      : account.displayName.characters.first.toUpperCase(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.displayName.isEmpty
                          ? 'Unnamed account'
                          : account.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      account.email,
                      style: const TextStyle(
                        color: Color(0xFF78858C),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Requests ${account.requestedRole.name} role')),
              if (account.matricNumber?.isNotEmpty == true)
                Chip(label: Text(account.matricNumber!)),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () async {
                final courseIds = await _chooseCourses(context);
                if (courseIds != null) onApprove(courseIds);
              },
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Approve account'),
            ),
          ),
        ],
      ),
    ),
  );

  Future<List<String>?> _chooseCourses(BuildContext context) {
    if (account.requestedRole != UniversityRole.student) {
      return showDialog<List<String>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Approve lecturer?'),
          content: Text(
            'Approve ${account.displayName} as a lecturer for this university?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, const <String>[]),
              child: const Text('Approve'),
            ),
          ],
        ),
      );
    }

    final selected = <String>{};
    return showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Approve student?'),
          content: SizedBox(
            width: 380,
            height: 380,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Approve ${account.displayName} as a student?'),
                const SizedBox(height: 10),
                if (courses.isEmpty)
                  const Text(
                    'There are no courses yet. This student can be assigned courses later.',
                    style: TextStyle(color: Color(0xFF78858C)),
                  )
                else ...[
                  const Text('Assign courses (optional):'),
                  const SizedBox(height: 4),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: courses
                          .map(
                            (course) => CheckboxListTile(
                              value: selected.contains(course.id),
                              contentPadding: EdgeInsets.zero,
                              title: Text(course.name),
                              subtitle: Text(course.schedule),
                              onChanged: (checked) => setState(() {
                                if (checked == true) {
                                  selected.add(course.id);
                                } else {
                                  selected.remove(course.id);
                                }
                              }),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected.toList()),
              child: const Text('Approve'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPendingAccounts extends StatelessWidget {
  const _NoPendingAccounts();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 36, color: Color(0xFF91A09F)),
          SizedBox(height: 10),
          Text(
            'No pending requests',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4),
          Text(
            'New account requests for this university will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF78858C), fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () =>
                context.read<AdminBloc>().add(const AdminDashboardRequested()),
            child: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
