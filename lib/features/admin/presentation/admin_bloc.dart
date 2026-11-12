import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/usecases/approve_pending_account.dart';
import '../domain/usecases/get_admin_dashboard.dart';
import '../domain/usecases/save_admin_course.dart';
import 'admin_event.dart';
import 'admin_state.dart';

class AdminBloc extends Bloc<AdminEvent, AdminState> {
  AdminBloc({
    required GetAdminDashboard getDashboard,
    required ApprovePendingAccount approveAccount,
    required SaveAdminCourse saveCourse,
  }) : _getDashboard = getDashboard,
       _approveAccount = approveAccount,
       _saveCourse = saveCourse,
       super(const AdminState()) {
    on<AdminDashboardRequested>(_onDashboardRequested);
    on<AdminAccountApprovalRequested>(_onApprovalRequested);
    on<AdminCourseSavedRequested>(_onCourseSaved);
  }

  final GetAdminDashboard _getDashboard;
  final ApprovePendingAccount _approveAccount;
  final SaveAdminCourse _saveCourse;

  Future<void> _onDashboardRequested(
    AdminDashboardRequested event,
    Emitter<AdminState> emit,
  ) async {
    emit(state.copyWith(status: AdminLoadStatus.loading));
    try {
      emit(
        state.copyWith(
          status: AdminLoadStatus.loaded,
          dashboard: await _getDashboard(),
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: AdminLoadStatus.failure,
          errorMessage: _message(error),
        ),
      );
    }
  }

  Future<void> _onApprovalRequested(
    AdminAccountApprovalRequested event,
    Emitter<AdminState> emit,
  ) async {
    try {
      final dashboard = await _approveAccount(
        account: event.account,
        courseIds: event.courseIds,
      );
      emit(
        state.copyWith(
          status: AdminLoadStatus.loaded,
          dashboard: dashboard,
          actionMessage: '${event.account.displayName} approved.',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: AdminLoadStatus.loaded,
          errorMessage: _message(error),
        ),
      );
    }
  }

  Future<void> _onCourseSaved(
    AdminCourseSavedRequested event,
    Emitter<AdminState> emit,
  ) async {
    try {
      final dashboard = await _saveCourse(
        courseId: event.courseId,
        name: event.name,
        schedule: event.schedule,
        lecturerIds: event.lecturerIds,
      );
      emit(
        state.copyWith(
          status: AdminLoadStatus.loaded,
          dashboard: dashboard,
          actionMessage: event.courseId == null
              ? '${event.name} created.'
              : '${event.name} updated.',
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: AdminLoadStatus.loaded,
          errorMessage: _message(error),
        ),
      );
    }
  }

  String _message(Object error) {
    if (error is StateError) return error.message;
    return error.toString();
  }
}
