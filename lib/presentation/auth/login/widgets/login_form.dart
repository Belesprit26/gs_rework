import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../di/locator.dart';
import '../../../../presentation/shared/widgets/app_text_field.dart';
import '../../../../presentation/shared/widgets/primary_button.dart';
import '../login_bloc.dart';

class LoginForm extends StatelessWidget {
  const LoginForm({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<LoginBloc>(),
      child: BlocListener<LoginBloc, LoginState>(
        listenWhen: (p, n) => p.forgotPasswordSent != n.forgotPasswordSent,
        listener: (context, state) {
          if (state.forgotPasswordSent) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Password reset email sent. Check your inbox.')),
            );
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Email
            BlocBuilder<LoginBloc, LoginState>(
              buildWhen: (p, n) => p.email != n.email,
              builder: (context, state) {
                return AppTextField(
                  hintText: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  onChanged: (v) => context.read<LoginBloc>().add(LoginEmailChanged(v)),
                );
              },
            ),
            const SizedBox(height: 16),

            // Password (with auto visibility toggle)
            BlocBuilder<LoginBloc, LoginState>(
              buildWhen: (p, n) => p.password != n.password,
              builder: (context, state) {
                return AppTextField(
                  hintText: 'Password',
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onChanged: (v) => context.read<LoginBloc>().add(LoginPasswordChanged(v)),
                );
              },
            ),
            const SizedBox(height: 4),

            // Forgot password
            Align(
              alignment: Alignment.centerRight,
              child: Builder(
                builder: (context) {
                  return TextButton(
                    onPressed: () =>
                        context.read<LoginBloc>().add(const LoginForgotPasswordPressed()),
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(color: Colors.black87, fontSize: 13),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),

            // Error text
            BlocBuilder<LoginBloc, LoginState>(
              buildWhen: (p, n) => p.status != n.status || p.error != n.error,
              builder: (context, state) {
                if (state.error == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    state.error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                );
              },
            ),

            // Submit
            BlocBuilder<LoginBloc, LoginState>(
              buildWhen: (p, n) => p.status != n.status,
              builder: (context, state) {
                return PrimaryButton(
                  label: state.status == LoginStatus.submitting ? 'Signing in…' : 'Sign in',
                  isLoading: state.status == LoginStatus.submitting,
                  onPressed: () => context.read<LoginBloc>().add(const LoginSubmitted()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
