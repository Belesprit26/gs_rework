import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../di/locator.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/neu_auth_widgets.dart';
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
              const SnackBar(
                  content: Text('Password reset email sent. Check your inbox.')),
            );
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Builder(builder: (context) {
              return AuthField(
                hintText: 'Email',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                onChanged: (v) =>
                    context.read<LoginBloc>().add(LoginEmailChanged(v)),
              );
            }),
            const SizedBox(height: 14),
            Builder(builder: (context) {
              return AuthField(
                hintText: 'Password',
                icon: Icons.lock_outline_rounded,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onChanged: (v) =>
                    context.read<LoginBloc>().add(LoginPasswordChanged(v)),
              );
            }),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Builder(builder: (context) {
                return GestureDetector(
                  onTap: () => context
                      .read<LoginBloc>()
                      .add(const LoginForgotPasswordPressed()),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Text(
                      'Forgot password?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkSecondary,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const Spacer(),
            BlocBuilder<LoginBloc, LoginState>(
              buildWhen: (p, n) => p.status != n.status || p.error != n.error,
              builder: (context, state) {
                if (state.error == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    state.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.critical),
                  ),
                );
              },
            ),
            BlocBuilder<LoginBloc, LoginState>(
              buildWhen: (p, n) => p.status != n.status,
              builder: (context, state) {
                final submitting = state.status == LoginStatus.submitting;
                return AuthCta(
                  label: submitting ? 'Signing in…' : 'Sign in',
                  isLoading: submitting,
                  onPressed: () =>
                      context.read<LoginBloc>().add(const LoginSubmitted()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
