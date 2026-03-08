import 'package:flutter/material.dart';

import 'login/widgets/login_form.dart';
import 'sign_up/widgets/sign_up_form.dart';
import 'widgets/auth_scaffold.dart';

enum AuthMode { signIn, signUp }

class AuthFlowView extends StatefulWidget {
  const AuthFlowView({super.key});

  @override
  State<AuthFlowView> createState() => _AuthFlowViewState();
}

class _AuthFlowViewState extends State<AuthFlowView> {
  AuthMode _mode = AuthMode.signIn;

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      header: _AuthHeader(mode: _mode),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _mode == AuthMode.signIn ? 'Sign in using email' : 'Sign up using email',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 50),
            child: _mode == AuthMode.signIn
                ? const LoginForm(key: ValueKey('login'))
                : const SignUpForm(key: ValueKey('signup')),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              setState(() {
                _mode = _mode == AuthMode.signIn ? AuthMode.signUp : AuthMode.signIn;
              });
            },
            child: Text(
              _mode == AuthMode.signIn
                  ? 'Don\'t have an account? Sign up'
                  : 'Already signed up? Log in',
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthHeader extends StatelessWidget {
  const _AuthHeader({required this.mode});

  final AuthMode mode;

  @override
  Widget build(BuildContext context) {
    final title = mode == AuthMode.signIn ? 'Welcome back' : 'Create account';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF7AD9FF), Color(0xFFBFEFFF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
