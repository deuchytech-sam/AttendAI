import 'package:equatable/equatable.dart';

import '../../../auth/domain/entities/university_account.dart';
import '../../../university/domain/entities/course.dart';
import '../../../university/domain/entities/university_role.dart';

class PendingAccount extends Equatable {
  const PendingAccount({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.universityId,
    required this.requestedRole,
    this.matricNumber,
  });

  final String uid;
  final String displayName;
  final String email;
  final String universityId;
  final UniversityRole requestedRole;
  final String? matricNumber;

  @override
  List<Object?> get props => [
    uid,
    displayName,
    email,
    universityId,
    requestedRole,
    matricNumber,
  ];
}

class AdminDashboard extends Equatable {
  const AdminDashboard({
    required this.pendingAccounts,
    required this.courses,
    this.lecturers = const [],
  });

  final List<PendingAccount> pendingAccounts;
  final List<Course> courses;
  final List<UniversityAccount> lecturers;

  @override
  List<Object?> get props => [pendingAccounts, courses, lecturers];
}
