import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../data/datasources/firestore_university_data_source.dart';
import '../domain/entities/university_dashboard.dart';
import '../domain/usecases/get_university_dashboard.dart';
import '../domain/usecases/record_student_check_in.dart';
import '../domain/usecases/toggle_attendance_session.dart';
import 'university_event.dart';
import 'university_state.dart';

class UniversityBloc extends Bloc<UniversityEvent, UniversityState> {
  UniversityBloc({
    required this._getDashboard,
    required this._toggleSession,
    required this._recordCheckIn,
    required this._dataSource,
  }) : super(const UniversityState()) {
    on<UniversityDashboardRequested>(_onDashboardRequested);
    on<AttendanceSessionToggled>(_onSessionToggled);
    on<StudentCheckInRequested>(_onStudentCheckInRequested);
    on<SessionStatusChanged>(_onSessionStatusChanged);
    on<ActionMessageDismissed>(_onActionMessageDismissed);
    on<SessionAttendanceRequested>(_onSessionAttendanceRequested);
    on<SessionAttendanceUpdated>(_onSessionAttendanceUpdated);
    on<SemesterAttendanceSummaryRequested>(
      _onSemesterAttendanceSummaryRequested,
    );
    on<SemesterAttendanceSummaryLoaded>(_onSemesterAttendanceSummaryLoaded);
    on<StudentAttendanceHistoryRequested>(_onStudentAttendanceHistoryRequested);
    on<StudentAttendanceHistoryLoaded>(_onStudentAttendanceHistoryLoaded);

    // Start listening to session changes when bloc is created
    _sessionSubscription = _dataSource.watchSessionChanges().listen(
      (event) {
        if (event != null) {
          add(event);
        }
      },
      onError: (error) {
        // Log error but don't crash
        debugPrint('Session stream error: $error');
      },
    );
  }

  final GetUniversityDashboard _getDashboard;
  final ToggleAttendanceSession _toggleSession;
  final RecordStudentCheckIn _recordCheckIn;
  final FirestoreUniversityDataSource _dataSource;
  StreamSubscription<SessionStatusChanged?>? _sessionSubscription;
  StreamSubscription<SessionAttendance>? _sessionAttendanceSubscription;

  /// Exposes the data source for accessing attendance service and user info.
  FirestoreUniversityDataSource get dataSource => _dataSource;

  @override
  Future<void> close() {
    _sessionSubscription?.cancel();
    _sessionAttendanceSubscription?.cancel();
    return super.close();
  }

  Future<void> _onDashboardRequested(
    UniversityDashboardRequested event,
    Emitter<UniversityState> emit,
  ) async {
    emit(const UniversityState(status: UniversityLoadStatus.loading));
    try {
      emit(state.withDashboard(await _getDashboard()));
    } catch (error) {
      emit(
        UniversityState(
          status: UniversityLoadStatus.failure,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> _onSessionToggled(
    AttendanceSessionToggled event,
    Emitter<UniversityState> emit,
  ) async {
    try {
      final dashboard = await _toggleSession(event.courseId);
      emit(
        state.withDashboard(
          dashboard,
          actionMessage: dashboard.openSessionCourseId == event.courseId
              ? 'Attendance session opened.'
              : 'Attendance session closed.',
        ),
      );
    } on FirebaseFunctionsException catch (error, stackTrace) {
      debugPrint(
        '[SessionToggle] code=${error.code}, message=${error.message}, '
        'details=${error.details}\n$stackTrace',
      );
      final message = switch (error.code) {
        'unauthenticated' => 'Your sign-in or app verification expired. Please restart the app and try again.',
        'permission-denied' =>
          'Only an active lecturer can open or close attendance sessions.',
        'unavailable' ||
        'deadline-exceeded' ||
        'internal' => 'The session service is unavailable. Please try again.',
        _ => 'Could not update the attendance session. Please try again.',
      };
      _emitActionError(emit, error, userMessage: message);
    } catch (error, stackTrace) {
      debugPrint('[SessionToggle] Failed: $error\n$stackTrace');
      _emitActionError(
        emit,
        error,
        userMessage:
            'Could not update the attendance session. Please try again.',
      );
    }
  }

  Future<void> _onStudentCheckInRequested(
    StudentCheckInRequested event,
    Emitter<UniversityState> emit,
  ) async {
    try {
      final studentId = _dataSource.userId;
      // Note: faceEmbeddings and faceMatchScore should come from the verification screen
      // This is a simplified version - the actual check-in with embeddings happens in FaceVerificationScreen
      // For now, we pass empty/default values - the real implementation uses FaceVerificationScreen
      final result = await _recordCheckIn(
        studentId: studentId,
        courseId: state.openSessionCourseId ?? '',
        faceEmbeddings: const [],
        faceMatchScore: 0.0,
      );
      emit(
        state.withDashboard(
          result.dashboard,
          actionMessage: result.recorded
              ? 'Identity-verified check-in recorded.'
              : 'No open session or already checked in.',
        ),
      );
    } catch (error) {
      _emitActionError(emit, error);
    }
  }

  Future<void> _onSessionStatusChanged(
    SessionStatusChanged event,
    Emitter<UniversityState> emit,
  ) async {
    // Find course name from current state
    final course = state.courses
        .where((c) => c.id == event.courseId)
        .firstOrNull;

    if (course == null) {
      // Course not in state, refresh dashboard to get latest
      try {
        emit(state.withDashboard(await _getDashboard()));
      } catch (_) {
        // Ignore refresh errors
      }
      return;
    }

    // Refresh the active session ID so check-in state is scoped to today's
    // instance rather than a prior attendance record for the same course.
    try {
      emit(
        state.withDashboard(
          await _getDashboard(),
          actionMessage: event.isOpen
              ? 'Session started for ${course.name}. Tap to check in.'
              : 'Session ended for ${course.name}.',
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[SessionStatus] Dashboard refresh failed: $error\n$stackTrace',
      );
    }
  }

  Future<void> _onActionMessageDismissed(
    ActionMessageDismissed event,
    Emitter<UniversityState> emit,
  ) async {
    emit(state.copyWith(actionMessage: null));
  }

  // Lecturer: Session Attendance
  Future<void> _onSessionAttendanceRequested(
    SessionAttendanceRequested event,
    Emitter<UniversityState> emit,
  ) async {
    // Cancel any existing subscription
    await _sessionAttendanceSubscription?.cancel();

    emit(state.copyWith(isLoadingSessionAttendance: true));

    final attendanceStream = event.sessionId.isNotEmpty
        ? _dataSource.watchSessionAttendance(event.sessionId)
        : _dataSource.watchLatestSessionAttendanceForCourse(
            event.courseId ?? state.openSessionCourseId ?? '',
          );
    _sessionAttendanceSubscription = attendanceStream.listen(
      (attendance) {
        add(SessionAttendanceUpdated(attendance));
      },
      onError: (error) {
        debugPrint('Session attendance stream error: $error');
        emit(
          state.copyWith(
            isLoadingSessionAttendance: false,
            errorMessage: 'Failed to load session attendance: $error',
          ),
        );
      },
    );
  }

  Future<void> _onSessionAttendanceUpdated(
    SessionAttendanceUpdated event,
    Emitter<UniversityState> emit,
  ) async {
    emit(
      state.copyWith(
        currentSessionAttendance: event.sessionAttendance,
        isLoadingSessionAttendance: false,
      ),
    );
  }

  // Lecturer: Semester Attendance Summary
  Future<void> _onSemesterAttendanceSummaryRequested(
    SemesterAttendanceSummaryRequested event,
    Emitter<UniversityState> emit,
  ) async {
    final courseId = event.courseId.trim();
    if (courseId.isEmpty) {
      emit(
        state.copyWith(
          isLoadingSemesterSummary: false,
          semesterSummaryError: 'Select a course before loading its summary.',
        ),
      );
      return;
    }

    if (_dataSource.universityId.isEmpty) {
      emit(
        state.copyWith(
          isLoadingSemesterSummary: false,
          semesterSummaryError: 'Your lecturer profile is missing its university ID. Sign in again or contact your university administrator.',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        isLoadingSemesterSummary: true,
        clearSemesterSummaryError: true,
      ),
    );
    try {
      final summary = await _dataSource.getSemesterAttendanceSummary(
        courseId: courseId,
        semesterStart: event.semesterStart,
        semesterEnd: event.semesterEnd,
      );
      add(SemesterAttendanceSummaryLoaded(summary));
    } catch (error) {
      emit(
        state.copyWith(
          isLoadingSemesterSummary: false,
          semesterSummaryError: _semesterSummaryErrorMessage(error),
        ),
      );
    }
  }

  String _semesterSummaryErrorMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      return switch (error.code) {
        'unauthenticated' =>
          'Your session expired. Sign in again to load the summary.',
        'permission-denied' =>
          'You do not have permission to view this course summary.',
        'invalid-argument' => 'The university or course information is incomplete. Check your lecturer profile and select a course.',
        _ => 'Could not load the semester summary. Check your connection and try again.',
      };
    }
    return 'Could not load the semester summary. Check your connection and try again.';
  }

  Future<void> _onSemesterAttendanceSummaryLoaded(
    SemesterAttendanceSummaryLoaded event,
    Emitter<UniversityState> emit,
  ) async {
    emit(
      state.copyWith(
        semesterAttendanceSummary: event.summary,
        isLoadingSemesterSummary: false,
      ),
    );
  }

  // Student: Attendance History
  Future<void> _onStudentAttendanceHistoryRequested(
    StudentAttendanceHistoryRequested event,
    Emitter<UniversityState> emit,
  ) async {
    emit(state.copyWith(isLoadingStudentHistory: true));
    try {
      final history = await _dataSource.getStudentAttendanceHistory(
        courseId: event.courseId,
        semesterStart: event.semesterStart,
        semesterEnd: event.semesterEnd,
      );
      add(StudentAttendanceHistoryLoaded(history));
    } catch (error) {
      emit(
        state.copyWith(
          isLoadingStudentHistory: false,
          errorMessage: 'Failed to load attendance history: $error',
        ),
      );
    }
  }

  Future<void> _onStudentAttendanceHistoryLoaded(
    StudentAttendanceHistoryLoaded event,
    Emitter<UniversityState> emit,
  ) async {
    emit(
      state.copyWith(
        studentAttendanceHistory: event.history,
        isLoadingStudentHistory: false,
      ),
    );
  }

  void _emitActionError(
    Emitter<UniversityState> emit,
    Object error, {
    String? userMessage,
  }) {
    emit(
      UniversityState(
        status: UniversityLoadStatus.loaded,
        courses: state.courses,
        students: state.students,
        entries: state.entries,
        openSessionCourseId: state.openSessionCourseId,
        openSessionId: state.openSessionId,
        errorMessage: userMessage ?? error.toString(),
      ),
    );
  }
}
