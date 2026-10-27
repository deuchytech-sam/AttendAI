import 'package:equatable/equatable.dart';

import '../domain/entities/admin_dashboard.dart';

enum AdminLoadStatus { initial, loading, loaded, failure }

class AdminState extends Equatable {
  const AdminState({
    this.status = AdminLoadStatus.initial,
    this.dashboard = const AdminDashboard(pendingAccounts: [], courses: []),
    this.errorMessage,
    this.actionMessage,
  });

  final AdminLoadStatus status;
  final AdminDashboard dashboard;
  final String? errorMessage;
  final String? actionMessage;

  AdminState copyWith({
    AdminLoadStatus? status,
    AdminDashboard? dashboard,
    String? errorMessage,
    String? actionMessage,
  }) => AdminState(
    status: status ?? this.status,
    dashboard: dashboard ?? this.dashboard,
    errorMessage: errorMessage,
    actionMessage: actionMessage,
  );

  @override
  List<Object?> get props => [status, dashboard, errorMessage, actionMessage];
}
