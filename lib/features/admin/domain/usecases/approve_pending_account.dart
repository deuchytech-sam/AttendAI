import '../entities/admin_dashboard.dart';
import '../repositories/admin_repository.dart';

class ApprovePendingAccount {
  const ApprovePendingAccount(this._repository);
  final AdminRepository _repository;

  Future<AdminDashboard> call({
    required PendingAccount account,
    required List<String> courseIds,
  }) => _repository.approveAccount(account: account, courseIds: courseIds);
}
