import 'package:equatable/equatable.dart';

import '../domain/entities/university_account.dart';
import '../../university/domain/entities/university_role.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

final class AuthSessionChanged extends AuthEvent {
  const AuthSessionChanged(this.account);
  final UniversityAccount? account;

  @override
  List<Object?> get props => [account];
}

final class AuthSignInSubmitted extends AuthEvent {
  const AuthSignInSubmitted({required this.email, required this.password});
  final String email;
  final String password;

  @override
  List<Object?> get props => [email, password];
}

final class AuthRegistrationSubmitted extends AuthEvent {
  const AuthRegistrationSubmitted({
    required this.email,
    required this.password,
    required this.displayName,
    required this.universityId,
    required this.requestedRole,
    this.matricNumber,
  });

  final String email;
  final String password;
  final String displayName;
  final String universityId;
  final UniversityRole requestedRole;
  final String? matricNumber;

  @override
  List<Object?> get props => [
    email,
    password,
    displayName,
    universityId,
    requestedRole,
    matricNumber,
  ];
}

final class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}

final class AuthVerificationEmailRequested extends AuthEvent {
  const AuthVerificationEmailRequested();
}

final class AuthAccountRefreshRequested extends AuthEvent {
  const AuthAccountRefreshRequested();
}

final class AuthFailureReported extends AuthEvent {
  const AuthFailureReported(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

final class AuthPasswordResetRequested extends AuthEvent {
  const AuthPasswordResetRequested({required this.email});
  final String email;

  @override
  List<Object?> get props => [email];
}
