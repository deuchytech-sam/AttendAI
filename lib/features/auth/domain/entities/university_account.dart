import 'package:equatable/equatable.dart';

import '../../../university/domain/entities/university_role.dart';

class UniversityAccount extends Equatable {
  const UniversityAccount({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.universityId,
    required this.requestedRole,
    required this.status,
    this.role,
    this.matricNumber,
    this.emailVerified = false,
  });

  final String uid;
  final String email;
  final String displayName;
  final String universityId;
  final UniversityRole requestedRole;
  final UniversityRole? role;
  final String? matricNumber;
  final AccountStatus status;
  final bool emailVerified;

  @override
  List<Object?> get props => [
    uid,
    email,
    displayName,
    universityId,
    requestedRole,
    role,
    matricNumber,
    status,
    emailVerified,
  ];
}

enum AccountStatus { pending, active }
