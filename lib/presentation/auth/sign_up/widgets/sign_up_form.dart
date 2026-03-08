import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../di/locator.dart';
import '../../../../presentation/shared/widgets/app_text_field.dart';
import '../../../../presentation/shared/widgets/primary_button.dart';
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
          BlocBuilder<SignUpBloc, SignUpState>(
            buildWhen: (p, n) => p.fullName != n.fullName,
            builder: (context, state) {
              return AppTextField(
                label: 'Create username',
                hintText: 'Your name',
                textInputAction: TextInputAction.next,
                onChanged: (v) => context.read<SignUpBloc>().add(SignUpFullNameChanged(v)),
              );
            },
          ),
          const SizedBox(height: 16),
          BlocBuilder<SignUpBloc, SignUpState>(
            buildWhen: (p, n) => p.email != n.email,
            builder: (context, state) {
              return AppTextField(
                label: 'Email',
                hintText: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                onChanged: (v) => context.read<SignUpBloc>().add(SignUpEmailChanged(v)),
              );
            },
          ),
          const SizedBox(height: 16),
          BlocBuilder<SignUpBloc, SignUpState>(
            buildWhen: (p, n) => p.password != n.password,
            builder: (context, state) {
              return AppTextField(
                label: 'Password',
                hintText: '••••••••',
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (v) =>
                    context.read<SignUpBloc>().add(SignUpPasswordChanged(v)),
              );
            },
          ),
          const SizedBox(height: 12),
          BlocBuilder<SignUpBloc, SignUpState>(
            buildWhen: (p, n) => p.status != n.status || p.error != n.error,
            builder: (context, state) {
              if (state.error == null) return const SizedBox.shrink();
              return Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              );
            },
          ),
          const SizedBox(height: 16),
          BlocBuilder<SignUpBloc, SignUpState>(
            buildWhen: (p, n) => p.status != n.status,
            builder: (context, state) {
              return PrimaryButton(
                label: state.status == SignUpStatus.submitting ? 'Creating…' : 'Create account',
                isLoading: state.status == SignUpStatus.submitting,
                onPressed: () => context.read<SignUpBloc>().add(const SignUpSubmitted()),
              );
            },
          ),
        ],
      ),
    );
  }
}

