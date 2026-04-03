import 'package:flutter_test/flutter_test.dart';

import 'package:gs_rework/core/utils/version_check.dart';
import 'package:gs_rework/domain/auth/auth_gate/auth_gate_context.dart';
import 'package:gs_rework/domain/auth/auth_gate/auth_gate_decision.dart';
import 'package:gs_rework/domain/auth/auth_gate/auth_gate_policy.dart';
import 'package:gs_rework/domain/auth/entities/auth_user.dart';
import 'package:gs_rework/domain/provisioning/provisioning_status.dart';

void main() {
  // ── Auth gate policy ────────────────────────────────────────────
  group('AuthGatePolicy', () {
    const policy = AuthGatePolicy();

    test('maintenance mode overrides everything', () {
      final ctx = AuthGateContext(
        user: const AuthUser(uid: 'u1', email: 'a@b.c'),
        isMaintenanceMode: true,
      );
      expect(policy.decide(ctx), AuthGateDecision.maintenance);
    });

    test('force upgrade when version unsupported', () {
      final ctx = AuthGateContext(
        user: const AuthUser(uid: 'u1', email: 'a@b.c'),
        isMinVersionSupported: false,
      );
      expect(policy.decide(ctx), AuthGateDecision.forceUpgrade);
    });

    test('signed-out when no user', () {
      const ctx = AuthGateContext(user: null);
      expect(policy.decide(ctx), AuthGateDecision.signedOut);
    });

    test('needs profile when incomplete', () {
      final ctx = AuthGateContext(
        user: const AuthUser(uid: 'u1', email: 'a@b.c'),
        isProfileComplete: false,
      );
      expect(policy.decide(ctx), AuthGateDecision.needsProfile);
    });

    test('ready when authenticated and complete', () {
      final ctx = AuthGateContext(
        user: const AuthUser(uid: 'u1', email: 'a@b.c'),
      );
      expect(policy.decide(ctx), AuthGateDecision.ready);
    });
  });

  // ── Version check ──────────────────────────────────────────────
  group('isVersionSupported', () {
    test('equal versions pass', () {
      expect(isVersionSupported('1.0.0', '1.0.0'), isTrue);
    });

    test('newer major passes', () {
      expect(isVersionSupported('2.0.0', '1.5.0'), isTrue);
    });

    test('older major fails', () {
      expect(isVersionSupported('1.0.0', '2.0.0'), isFalse);
    });

    test('newer patch passes', () {
      expect(isVersionSupported('1.0.2', '1.0.1'), isTrue);
    });

    test('older minor fails', () {
      expect(isVersionSupported('1.0.9', '1.1.0'), isFalse);
    });
  });

  // ── Provisioning status ────────────────────────────────────────
  group('ProvisioningStatus', () {
    test('fromByte round-trips all known codes', () {
      for (final status in ProvisioningStatus.values) {
        expect(ProvisioningStatus.fromByte(status.code), status);
      }
    });

    test('unknown byte falls back to error', () {
      expect(ProvisioningStatus.fromByte(0xFF), ProvisioningStatus.error);
    });

    test('terminal states are correct', () {
      expect(ProvisioningStatus.complete.isTerminal, isTrue);
      expect(ProvisioningStatus.bleOnlyOk.isTerminal, isTrue);
      expect(ProvisioningStatus.wifiFail.isTerminal, isTrue);
      expect(ProvisioningStatus.error.isTerminal, isTrue);
      expect(ProvisioningStatus.idle.isTerminal, isFalse);
      expect(ProvisioningStatus.connecting.isTerminal, isFalse);
      expect(ProvisioningStatus.wifiOk.isTerminal, isFalse);
    });

    test('success states are correct', () {
      expect(ProvisioningStatus.complete.isSuccess, isTrue);
      expect(ProvisioningStatus.bleOnlyOk.isSuccess, isTrue);
      expect(ProvisioningStatus.wifiFail.isSuccess, isFalse);
      expect(ProvisioningStatus.error.isSuccess, isFalse);
    });
  });
}
