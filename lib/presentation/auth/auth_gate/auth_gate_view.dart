import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../di/locator.dart';
import '../../../domain/auth/auth_gate/auth_gate_decision.dart';
import '../../dashboard/dashboard_page.dart';
import '../auth_flow_view.dart';
import 'auth_gate_cubit.dart';

class AuthGateView extends StatelessWidget {
  const AuthGateView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<AuthGateCubit>(),
      child: BlocBuilder<AuthGateCubit, AuthGateState>(
        buildWhen: (p, n) => p.decision != n.decision || p.user != n.user,
        builder: (context, state) {
          switch (state.decision) {
            case AuthGateDecision.loading:
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            case AuthGateDecision.signedOut:
              return const AuthFlowView();
            case AuthGateDecision.needsProfile:
              return const Scaffold(body: Center(child: Text('Profile incomplete')));
            case AuthGateDecision.maintenance:
              return const Scaffold(body: Center(child: Text('Maintenance mode')));
            case AuthGateDecision.forceUpgrade:
              return const Scaffold(body: Center(child: Text('Update required')));
            case AuthGateDecision.ready:
              return const DashboardPage();
          }
        },
      ),
    );
  }
}
