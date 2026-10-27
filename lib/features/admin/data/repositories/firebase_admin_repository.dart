import '../../domain/entities/admin_dashboard.dart';
import '../../domain/repositories/admin_repository.dart';
import '../datasources/firestore_admin_data_source.dart';

class FirebaseAdminRepository implements AdminRepository {
  const FirebaseAdminRepository(this._dataSource);
  final FirestoreAdminDataSource _dataSource;

  @override
  Future<AdminDashboard> getDashboard() => _dataSource.getDashboard();

  @override
  Future<AdminDashboard> approveAccount({
    required PendingAccount account,
    required List<String> courseIds,
  }) =>
      _dataSource.approveAccount(pendingAccount: account, courseIds: courseIds);
}
