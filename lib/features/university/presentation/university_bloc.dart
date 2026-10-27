import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/entities/university_dashboard.dart';
import '../domain/usecases/add_university_course.dart';
import '../domain/usecases/enroll_university_student.dart';
import '../domain/usecases/get_university_dashboard.dart';
import '../domain/usecases/record_student_check_in.dart';
import '../domain/usecases/toggle_attendance_session.dart';
import 'university_event.dart';
import 'university_state.dart';

class UniversityBloc extends Bloc<UniversityEvent, UniversityState> {
  UniversityBloc({
    required this._getDashboard,
    required this._addCourse,
    required this._enrollStudent,
    required this._toggleSession,
    required this._recordCheckIn,
  }) : super(const UniversityState()) {
    on<UniversityDashboardRequested>(_onDashboardRequested);
    on<UniversityCourseAdded>(_onCourseAdded);
    on<UniversityStudentEnrolled>(_onStudentEnrolled);
    on<AttendanceSessionToggled>(_onSessionToggled);
    on<StudentCheckInRequested>(_onStudentCheckInRequested);
  }

  final GetUniversityDashboard _getDashboard;
  final AddUniversityCourse _addCourse;
  final EnrollUniversityStudent _enrollStudent;
  final ToggleAttendanceSession _toggleSession;
  final RecordStudentCheckIn _recordCheckIn;

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

  Future<void> _onCourseAdded(
    UniversityCourseAdded event,
    Emitter<UniversityState> emit,
  ) async {
    await _updateDashboard(
      emit,
      _addCourse(
        name: event.name,
        lecturer: event.lecturer,
        schedule: event.schedule,
      ),
      actionMessage: '${event.name} added',
    );
  }

  Future<void> _onStudentEnrolled(
    UniversityStudentEnrolled event,
    Emitter<UniversityState> emit,
  ) async {
    await _updateDashboard(
      emit,
      _enrollStudent(
        name: event.name,
        matricNumber: event.matricNumber,
        courseId: event.courseId,
      ),
      actionMessage: '${event.name} enrolled',
    );
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
    } catch (error) {
      _emitActionError(emit, error);
    }
  }

  Future<void> _onStudentCheckInRequested(
    StudentCheckInRequested event,
    Emitter<UniversityState> emit,
  ) async {
    try {
      final result = await _recordCheckIn();
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

  Future<void> _updateDashboard(
    Emitter<UniversityState> emit,
    Future<UniversityDashboard> update, {
    required String actionMessage,
  }) async {
    try {
      emit(state.withDashboard(await update, actionMessage: actionMessage));
    } catch (error) {
      _emitActionError(emit, error);
    }
  }

  void _emitActionError(Emitter<UniversityState> emit, Object error) {
    emit(
      UniversityState(
        status: UniversityLoadStatus.loaded,
        courses: state.courses,
        students: state.students,
        entries: state.entries,
        openSessionCourseId: state.openSessionCourseId,
        errorMessage: error.toString(),
      ),
    );
  }
}
