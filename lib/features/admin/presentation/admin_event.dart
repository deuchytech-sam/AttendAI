import 'package:equatable/equatable.dart';

import '../domain/entities/admin_dashboard.dart';

sealed class AdminEvent extends Equatable {
  const AdminEvent();

  @override
  List<Object?> get props => [];
}

final class AdminDashboardRequested extends AdminEvent {
  const AdminDashboardRequested();
}

final class AdminAccountApprovalRequested extends AdminEvent {
  const AdminAccountApprovalRequested({
    required this.account,
    required this.courseIds,
  });

  final PendingAccount account;
  final List<String> courseIds;

  @override
  List<Object?> get props => [account, courseIds];
}
