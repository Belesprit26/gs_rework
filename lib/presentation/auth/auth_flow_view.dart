import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'login/widgets/login_form.dart';
import 'sign_up/widgets/sign_up_form.dart';
import 'widgets/neu_auth_widgets.dart';

enum AuthMode { signIn, signUp }

/// The auth screen, per DESIGN_LANGUAGE.md ("Applied: the auth
/// screens"): one `neuBase` surface edge to edge, the brand mark on a
/// raised plinth as the single ramp moment, and the grooved mode well
/// making sign-up an explicit lane. Depth budget: badge, mode well,
/// fields, CTA — everything else flat.
class AuthFlowView extends StatefulWidget {
  const AuthFlowView({super.key});

  @override
  State<AuthFlowView> createState() => _AuthFlowViewState();
}

class _AuthFlowViewState extends State<AuthFlowView> {
  AuthMode _mode = AuthMode.signIn;

  @override
  Widget build(BuildContext context) {
    final signIn = _mode == AuthMode.signIn;

    return Scaffold(
      backgroundColor: AppColors.neuBase,
      body: SafeArea(
        // Scrollable so the CTA stays reachable with the keyboard open
        // on small phones; the spacer keeps it anchored low otherwise.
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 18),
                      const Center(child: AuthLogoBadge()),
                      const SizedBox(height: 22),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeOutCubic,
                        child: Column(
                          key: ValueKey(_mode),
                          children: [
                            Text(
                              signIn ? 'Welcome back' : 'Create your account',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              signIn
                                  ? 'Sign in to keep an eye on your geyser.'
                                  : 'One account for every geyser in the house.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.45,
                                color: AppColors.inkSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                      AuthModeWell(
                        labels: const ['Sign in', 'Create account'],
                        activeIndex: signIn ? 0 : 1,
                        onSelected: (i) => setState(() {
                          _mode = i == 0 ? AuthMode.signIn : AuthMode.signUp;
                        }),
                      ),
                      const SizedBox(height: 24),
                      // Fills the remaining height; each form carries its
                      // own bottom-anchored CTA via an internal Spacer.
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 100),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOutCubic,
                          layoutBuilder: (current, previous) => Stack(
                            fit: StackFit.expand,
                            children: [...previous, if (current != null) current],
                          ),
                          child: signIn
                              ? const LoginForm(key: ValueKey('login'))
                              : const SignUpForm(key: ValueKey('signup')),
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
