import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/entities/university_account.dart';
import '../domain/usecases/get_current_account.dart';
import '../domain/usecases/register_university_account.dart';
import '../domain/usecases/resend_email_verification.dart';
import '../domain/usecases/send_password_reset_email.dart';
import '../domain/usecases/sign_in.dart';
import '../domain/usecases/sign_out.dart';
import '../domain/usecases/watch_university_account.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required this._getCurrentAccount,
    required this._register,
    required this._signOut,
    required this._resendVerification,
    required this._signIn,
    required this._sendPasswordResetEmail,
    required WatchUniversityAccount watchAccount,
  }) : super(const AuthState()) {
    on<AuthSessionChanged>(_onSessionChanged);
    on<AuthSignInSubmitted>(_onSignInSubmitted);
    on<AuthRegistrationSubmitted>(_onRegistrationSubmitted);
    on<AuthSignOutRequested>(_onSignOutRequested);
    on<AuthVerificationEmailRequested>(_onVerificationRequested);
    on<AuthAccountRefreshRequested>(_onAccountRefreshRequested);
    on<AuthPasswordResetRequested>(_onPasswordResetRequested);
    on<AuthFailureReported>((event, emit) {
      emit(AuthState(status: AuthStatus.failure, message: event.message));
    });
    _subscription = watchAccount().listen(
      (account) => add(AuthSessionChanged(account)),
      onError: (Object error) =>
          add(AuthFailureReported(_friendlyError(error))),
    );
  }

  final GetCurrentAccount _getCurrentAccount;
  final SignIn _signIn;
  final RegisterUniversityAccount _register;
  final SignOut _signOut;
  final ResendEmailVerification _resendVerification;
  final SendPasswordResetEmail _sendPasswordResetEmail;
  late final StreamSubscription<UniversityAccount?> _subscription;

  void _onSessionChanged(AuthSessionChanged event, Emitter<AuthState> emit) {
    final account = event.account;
    emit(
      AuthState(
        status: account == null
            ? AuthStatus.signedOut
            : account.status == AccountStatus.active
            ? AuthStatus.authenticated
            : AuthStatus.pending,
        account: account,
      ),
    );
  }

  Future<void> _onSignInSubmitted(
    AuthSignInSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthState(status: AuthStatus.loading));
    try {
      await _signIn(email: event.email, password: event.password);
      emit(_stateFor(await _getCurrentAccount()));
    } catch (error) {
      emit(
        AuthState(status: AuthStatus.signedOut, message: _friendlyError(error)),
      );
    }
  }

  Future<void> _onRegistrationSubmitted(
    AuthRegistrationSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthState(status: AuthStatus.loading));
    try {
      await _register(
        email: event.email,
        password: event.password,
        displayName: event.displayName,
        universityId: event.universityId,
        requestedRole: event.requestedRole,
        matricNumber: event.matricNumber,
      );
      emit(_stateFor(await _getCurrentAccount()));
    } catch (error) {
      emit(
        AuthState(status: AuthStatus.signedOut, message: _friendlyError(error)),
      );
    }
  }

  Future<void> _onSignOutRequested(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthState(status: AuthStatus.loading));
    try {
      await _signOut();
      emit(const AuthState(status: AuthStatus.signedOut));
    } catch (error) {
      emit(
        AuthState(status: AuthStatus.failure, message: _friendlyError(error)),
      );
    }
  }

  Future<void> _onVerificationRequested(
    AuthVerificationEmailRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await _resendVerification();
      emit(state.copyWith(message: 'Verification email sent.'));
    } catch (error) {
      emit(state.copyWith(message: _friendlyError(error)));
    }
  }

  Future<void> _onAccountRefreshRequested(
    AuthAccountRefreshRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      emit(_stateFor(await _getCurrentAccount()));
    } catch (error) {
      emit(state.copyWith(message: _friendlyError(error)));
    }
  }

  Future<void> _onPasswordResetRequested(
    AuthPasswordResetRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await _sendPasswordResetEmail(email: event.email);
      emit(state.copyWith(message: 'Password reset email sent. Check your inbox.'));
    } catch (error) {
      emit(state.copyWith(message: _friendlyError(error)));
    }
  }

  AuthState _stateFor(UniversityAccount? account) => AuthState(
    status: account == null
        ? AuthStatus.signedOut
        : account.status == AccountStatus.active
        ? AuthStatus.authenticated
        : AuthStatus.pending,
    account: account,
  );

  String _friendlyError(Object error) {
    final code = error is FirebaseAuthException ? error.code : '';
    return switch (code) {
      'invalid-email' => 'Enter a valid email address.',
      'user-not-found' ||
      'invalid-credential' ||
      'wrong-password' => 'Email or password is incorrect.',
      'email-already-in-use' => 'An account already exists for this email.',
      'weak-password' => 'Use a stronger password (at least 6 characters).',
      'network-request-failed' => 'Check your internet connection and retry.',
      _ => error.toString(),
    };
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await super.close();
  }
}
