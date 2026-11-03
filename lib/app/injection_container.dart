import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../features/admin/data/datasources/firestore_admin_data_source.dart';
import '../features/admin/data/repositories/firebase_admin_repository.dart';
import '../features/admin/domain/usecases/approve_pending_account.dart';
import '../features/admin/domain/usecases/get_admin_dashboard.dart';
import '../features/admin/presentation/admin_bloc.dart';
import '../features/admin/presentation/admin_event.dart';
import '../features/auth/data/datasources/firebase_auth_data_source.dart';
import '../features/auth/data/repositories/firebase_auth_repository.dart';
import '../features/auth/domain/entities/university_account.dart';
import '../features/auth/domain/usecases/get_current_account.dart';
import '../features/auth/domain/usecases/register_university_account.dart';
import '../features/auth/domain/usecases/resend_email_verification.dart';
import '../features/auth/domain/usecases/send_password_reset_email.dart';
import '../features/auth/domain/usecases/sign_in.dart';
import '../features/auth/domain/usecases/sign_out.dart';
import '../features/auth/domain/usecases/watch_university_account.dart';
import '../features/auth/presentation/auth_bloc.dart';
import '../features/biometrics/data/repositories/face_liveness_biometric_repository.dart';
import '../features/biometrics/domain/services/face_liveness_service.dart';
import '../features/biometrics/domain/repositories/biometric_repository.dart';
import '../features/biometrics/domain/usecases/enroll_student_biometric.dart';
import '../features/notifications/notification_service.dart';
import '../features/university/data/datasources/firestore_university_data_source.dart';
import '../features/university/data/repositories/firebase_university_repository.dart';
import '../features/university/domain/usecases/add_university_course.dart';
import '../features/university/domain/usecases/enroll_university_student.dart';
import '../features/university/domain/usecases/get_university_dashboard.dart';
import '../features/university/domain/usecases/record_student_check_in.dart';
import '../features/university/domain/usecases/toggle_attendance_session.dart';
import '../features/university/presentation/university_bloc.dart';
import '../features/university/presentation/university_event.dart';

NotificationService createNotificationService() => NotificationService();

AuthBloc createAuthBloc() {
  final repository = FirebaseAuthRepository(
    FirebaseAuthDataSource(FirebaseAuth.instance, FirebaseFirestore.instance),
  );
  return AuthBloc(
    watchAccount: WatchUniversityAccount(repository),
    getCurrentAccount: GetCurrentAccount(repository),
    signIn: SignIn(repository),
    register: RegisterUniversityAccount(repository),
    signOut: SignOut(repository),
    resendVerification: ResendEmailVerification(repository),
    sendPasswordResetEmail: SendPasswordResetEmail(repository),
    notificationService: createNotificationService(),
  );
}

AdminBloc createAdminBloc(UniversityAccount account) {
  final repository = FirebaseAdminRepository(
    FirestoreAdminDataSource(
      firestore: FirebaseFirestore.instance,
      auth: FirebaseAuth.instance,
      account: account,
    ),
  );
  return AdminBloc(
    getDashboard: GetAdminDashboard(repository),
    approveAccount: ApprovePendingAccount(repository),
  )..add(const AdminDashboardRequested());
}

// Singleton FaceLivenessService (uses FaceIdentityService internally with SharedPreferences)
FaceLivenessService createFaceLivenessService() {
  return FaceLivenessService();
}

BiometricRepository createBiometricRepository() {
  final livenessService = createFaceLivenessService();
  return FaceLivenessBiometricRepository(livenessService: livenessService);
}

EnrollStudentBiometric createEnrollStudentBiometric() {
  return EnrollStudentBiometric(createBiometricRepository());
}

UniversityBloc createUniversityBloc(UniversityAccount account) {
  final livenessService = createFaceLivenessService();
  final biometricRepository = FaceLivenessBiometricRepository(
    livenessService: livenessService,
  );

  final dataSource = FirestoreUniversityDataSource(
    FirebaseFirestore.instance,
    account,
    biometricRepository,
  );
  final repository = FirebaseUniversityRepository(dataSource);
  return UniversityBloc(
    getDashboard: GetUniversityDashboard(repository),
    addCourse: AddUniversityCourse(repository),
    enrollStudent: EnrollUniversityStudent(repository),
    toggleSession: ToggleAttendanceSession(repository),
    recordCheckIn: RecordStudentCheckIn(repository),
    dataSource: dataSource,
  )..add(const UniversityDashboardRequested());
}