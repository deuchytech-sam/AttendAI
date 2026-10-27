import 'package:equatable/equatable.dart';

import '../domain/entities/university_account.dart';

enum AuthStatus {
  checking,
  loading,
  signedOut,
  pending,
  authenticated,
  failure,
}

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.checking,
    this.account,
    this.message,
  });

  final AuthStatus status;
  final UniversityAccount? account;
  final String? message;

  AuthState copyWith({
    AuthStatus? status,
    UniversityAccount? account,
    String? message,
  }) => AuthState(
    status: status ?? this.status,
    account: account ?? this.account,
    message: message,
  );

  @override
  List<Object?> get props => [status, account, message];
}
