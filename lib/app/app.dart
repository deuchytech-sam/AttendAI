import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/auth_gate_page.dart';
import '../features/auth/presentation/auth_bloc.dart';
import 'injection_container.dart';
import 'theme/app_theme.dart';

class AttendAiApp extends StatelessWidget {
  const AttendAiApp({super.key});

  static final _router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthGatePage()),
    ],
  );

  @override
  Widget build(BuildContext context) => BlocProvider<AuthBloc>(
    create: (_) => createAuthBloc(),
    child: MaterialApp.router(
      title: 'AttendAI University',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: _router,
    ),
  );
}
