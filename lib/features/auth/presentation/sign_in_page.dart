import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../university/domain/entities/university_role.dart';
import 'auth_bloc.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, this.errorMessage});
  final String? errorMessage;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  final _universityId = TextEditingController();
  final _matricNumber = TextEditingController();
  bool _registering = false;
  UniversityRole _requestedRole = UniversityRole.student;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    _universityId.dispose();
    _matricNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.fact_check_rounded, size: 58),
                  const SizedBox(height: 14),
                  Text(
                    'AttendAI University',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _registering
                        ? 'Create an account. Your role requires university approval.'
                        : 'Sign in to your university account.',
                    textAlign: TextAlign.center,
                  ),
                  if (widget.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      widget.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_registering) ...[
                    TextFormField(
                      controller: _displayName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Full name'),
                      validator: (value) =>
                          _required(value, 'Enter your name.'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _universityId,
                      decoration: const InputDecoration(
                        labelText: 'University code',
                        hintText:
                            'Shared university ID, e.g. attendai-university',
                      ),
                      validator: (value) => _validateUniversityId(value),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<UniversityRole>(
                      initialValue: _requestedRole,
                      decoration: const InputDecoration(
                        labelText: 'Request account role',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: UniversityRole.student,
                          child: Text('Student'),
                        ),
                        DropdownMenuItem(
                          value: UniversityRole.lecturer,
                          child: Text('Lecturer'),
                        ),
                      ],
                      onChanged: (role) {
                        if (role != null) setState(() => _requestedRole = role);
                      },
                    ),
                    if (_requestedRole == UniversityRole.student) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _matricNumber,
                        decoration: const InputDecoration(
                          labelText: 'Matriculation number',
                          hintText: 'e.g. COMP/26/ENG/0001',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (value) => _required(value, 'Enter your email.'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: [
                      _registering
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (value) =>
                        _required(value, 'Enter your password.'),
                  ),
                  const SizedBox(height: 20),
                  BlocBuilder<AuthBloc, AuthState>(
                    builder: (context, state) => FilledButton(
                      onPressed: state.status == AuthStatus.loading
                          ? null
                          : _submit,
                      child: state.status == AuthStatus.loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_registering ? 'Create account' : 'Sign in'),
                    ),
                  ),
                  if (!_registering) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => _showForgotPasswordDialog(context),
                      child: const Text('Forgot password?'),
                    ),
                  ],
                  TextButton(
                    onPressed: () =>
                        setState(() => _registering = !_registering),
                    child: Text(
                      _registering
                          ? 'Already have an account? Sign in'
                          : 'New here? Create an account',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  String? _required(String? value, String message) =>
      value == null || value.trim().isEmpty ? message : null;

  String? _validateUniversityId(String? value) {
    final requiredError = _required(value, 'Enter your university ID.');
    if (requiredError != null) return requiredError;
    if (value!.trim().contains('/')) {
      return 'University ID cannot contain a slash (/).';
    }
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final bloc = context.read<AuthBloc>();
    if (_registering) {
      bloc.add(
        AuthRegistrationSubmitted(
          email: _email.text,
          password: _password.text,
          displayName: _displayName.text,
          universityId: _universityId.text,
          requestedRole: _requestedRole,
          matricNumber: _matricNumber.text.trim().isEmpty
              ? null
              : _matricNumber.text,
        ),
      );
    } else {
      bloc.add(
        AuthSignInSubmitted(email: _email.text, password: _password.text),
      );
    }
  }

  void _showForgotPasswordDialog(BuildContext context) {
    final emailController = TextEditingController(text: _email.text);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter your email address to receive a password reset link.'),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'you@example.com',
              ),
              autofillHints: const [AutofillHints.email],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter your email.')),
                );
                return;
              }
              Navigator.pop(dialogContext);
              context.read<AuthBloc>().add(
                AuthPasswordResetRequested(email: email),
              );
            },
            child: const Text('Send Reset Link'),
          ),
        ],
      ),
    );
  }
}
