import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../di/locator.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/neu_auth_widgets.dart';
import '../sign_up_bloc.dart';

class SignUpForm extends StatelessWidget {
  const SignUpForm({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<SignUpBloc>(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Builder(builder: (context) {
            return AuthField(
              hintText: 'Full name',
              icon: Icons.person_outline_rounded,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              onChanged: (v) =>
                  context.read<SignUpBloc>().add(SignUpFullNameChanged(v)),
            );
          }),
          const SizedBox(height: 14),
          Builder(builder: (context) {
            return AuthField(
              hintText: 'Email',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              onChanged: (v) =>
                  context.read<SignUpBloc>().add(SignUpEmailChanged(v)),
            );
          }),
          const SizedBox(height: 14),
          Builder(builder: (context) {
            return AuthField(
              hintText: 'Password',
              icon: Icons.lock_outline_rounded,
              obscureText: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (v) =>
                  context.read<SignUpBloc>().add(SignUpPasswordChanged(v)),
            );
          }),
          const Padding(
            padding: EdgeInsets.only(top: 7, left: 4),
            child: Text(
              'At least 6 characters.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          const Spacer(),
          BlocBuilder<SignUpBloc, SignUpState>(
            buildWhen: (p, n) => p.status != n.status || p.error != n.error,
            builder: (context, state) {
              if (state.error == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  state.error!,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.critical),
                ),
              );
            },
          ),
          BlocBuilder<SignUpBloc, SignUpState>(
            buildWhen: (p, n) => p.status != n.status,
            builder: (context, state) {
              final submitting = state.status == SignUpStatus.submitting;
              return AuthCta(
                label: submitting ? 'Creating…' : 'Create account',
                isLoading: submitting,
                onPressed: () =>
                    context.read<SignUpBloc>().add(const SignUpSubmitted()),
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.only(top: 14, left: 6, right: 6),
            child: Text(
              'By continuing you agree to the Terms and Privacy Policy.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
