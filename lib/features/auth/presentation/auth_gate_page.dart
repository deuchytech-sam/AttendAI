import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/injection_container.dart';
import '../../admin/presentation/admin_dashboard_page.dart';
import '../../admin/presentation/admin_bloc.dart';
import '../../university/presentation/university_bloc.dart';
import '../../university/presentation/university_home_page.dart';
import '../domain/entities/university_account.dart';
import '../../university/domain/entities/university_role.dart';
import 'auth_bloc.dart';
import 'auth_event.dart';
import 'auth_state.dart';
import 'sign_in_page.dart';

class AuthGatePage extends StatelessWidget {
  const AuthGatePage({super.key});

  @override
  Widget build(BuildContext context) => BlocConsumer<AuthBloc, AuthState>(
    listener: (context, state) {
      final message = state.message;
      if (message != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    },
    builder: (context, state) {
      switch (state.status) {
        case AuthStatus.checking:
        case AuthStatus.loading:
          return const _AuthLoadingPage();
        case AuthStatus.authenticated:
          final account = state.account!;
          if (account.role == UniversityRole.admin) {
            return BlocProvider<AdminBloc>(
              key: ValueKey(account.uid),
              create: (_) => createAdminBloc(account),
              child: AdminDashboardPage(account: account),
            );
          }
          return BlocProvider<UniversityBloc>(
            key: ValueKey(account.uid),
            create: (_) => createUniversityBloc(account),
            child: UniversityHomePage(
              role: account.role!,
              displayName: account.displayName,
              universityId: account.universityId,
              matricNumber: account.matricNumber,
              onSignOut: () =>
                  context.read<AuthBloc>().add(const AuthSignOutRequested()),
            ),
          );
        case AuthStatus.pending:
          return _PendingAccountPage(account: state.account!);
        case AuthStatus.signedOut:
        case AuthStatus.failure:
          return SignInPage(errorMessage: state.message);
      }
    },
  );
}

class _AuthLoadingPage extends StatelessWidget {
  const _AuthLoadingPage();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _PendingAccountPage extends StatelessWidget {
  const _PendingAccountPage({required this.account});
  final UniversityAccount account;

  @override
  Widget build(BuildContext context) {
    final universityIdValid =
        account.universityId.trim().isNotEmpty &&
        !account.universityId.contains('/');
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.hourglass_top_rounded, size: 58),
                  const SizedBox(height: 18),
                  Text(
                    !universityIdValid
                        ? 'University ID needs correction'
                        : account.emailVerified
                        ? 'Awaiting university approval'
                        : 'Verify your email',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    !universityIdValid
                        ? 'This account has an invalid university ID. Sign out and contact your university administrator to correct the account profile.'
                        : account.emailVerified
                        ? 'Your ${account.requestedRole.name} account for ${account.universityId} is pending approval by a university administrator.'
                        : 'We sent a verification link to ${account.email}. Verify it, then refresh your account status. A university administrator must also approve your role.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (!account.emailVerified)
                    FilledButton.tonal(
                      onPressed: () => context.read<AuthBloc>().add(
                        const AuthVerificationEmailRequested(),
                      ),
                      child: const Text('Resend verification email'),
                    ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => context.read<AuthBloc>().add(
                      const AuthAccountRefreshRequested(),
                    ),
                    child: const Text('Refresh account status'),
                  ),
                  TextButton(
                    onPressed: () => context.read<AuthBloc>().add(
                      const AuthSignOutRequested(),
                    ),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
