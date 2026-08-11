import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../di/locator.dart';
import '../../domain/provisioning/provisioning_status.dart';
import '../shared/feedback/haptics.dart';
import '../shared/widgets/app_text_field.dart';
import '../shared/widgets/neu/neu.dart';
import '../theme/app_colors.dart';
import 'provisioning_cubit.dart';

/// Shows the provisioning bottom sheet modal.
///
/// Call this after a successful BLE connection to configure the device.
Future<bool?> showProvisioningSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.paper,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => BlocProvider(
      create: (_) => getIt<ProvisioningCubit>()..init(),
      child: const _ProvisioningSheetBody(),
    ),
  );
}

class _ProvisioningSheetBody extends StatelessWidget {
  const _ProvisioningSheetBody();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return BlocConsumer<ProvisioningCubit, ProvisioningState>(
          // Milestone haptics for a flow the user is actively watching:
          // a quiet tick as WiFi comes up, the success double-tick or the
          // blocked thud when the run resolves.
          listenWhen: (prev, curr) =>
              prev.step != curr.step ||
              prev.deviceStatus != curr.deviceStatus,
          listener: (context, state) {
            if (state.step == ProvisioningStep.result) {
              if (state.isSuccess) {
                Haptics.success();
              } else {
                Haptics.blocked();
              }
            } else if (state.deviceStatus == ProvisioningStatus.wifiOk) {
              Haptics.tap();
            }
          },
          builder: (context, state) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // (Drag handle comes from showDragHandle.)
                  const SizedBox(height: 4),

                  // ── Content ──────────────────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: switch (state.step) {
                        ProvisioningStep.configure => _ConfigureView(state: state),
                        ProvisioningStep.inProgress => _ProgressView(state: state),
                        ProvisioningStep.result => _ResultView(state: state),
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// ── STEP 1: Configure ────────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════

class _ConfigureView extends StatefulWidget {
  const _ConfigureView({required this.state});

  final ProvisioningState state;

  @override
  State<_ConfigureView> createState() => _ConfigureViewState();
}

class _ConfigureViewState extends State<_ConfigureView> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _ssidController;
  late final TextEditingController _passwordController;
  bool _fieldsInitialised = false;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController();
    _ssidController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant _ConfigureView old) {
    super.didUpdateWidget(old);

    if (_fieldsInitialised) return;

    // Pre-fill from device state (already provisioned).
    if (widget.state.isAlreadyProvisioned &&
        widget.state.initialNickname.isNotEmpty) {
      _nicknameController.text = widget.state.initialNickname;
      // Pre-fill SSID from device or phone fallback.
      if (widget.state.wifiEnabled && widget.state.ssid.isNotEmpty) {
        _ssidController.text = widget.state.ssid;
      }
      _fieldsInitialised = true;
      return;
    }

    // Pre-fill SSID from phone's current WiFi (new provisioning).
    if (!widget.state.isAlreadyProvisioned &&
        widget.state.currentSsid != null &&
        widget.state.currentSsid!.isNotEmpty) {
      _ssidController.text = widget.state.currentSsid!;
      _fieldsInitialised = true;
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  ProvisioningState get state => widget.state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<ProvisioningCubit>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Heading ────────────────────────────────────────────
        Text(
          'Configure GeyserSwitch',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),

        // ── Connection chips ───────────────────────────────────
        Row(
          children: [
            const _ConnectionChip(
              icon: Icons.bluetooth_connected,
              label: 'Bluetooth',
              isActive: true,
              activeColor: AppColors.rampBlue,
              onTap: null, // Always active, not toggleable.
            ),
            const SizedBox(width: 12),
            _ConnectionChip(
              icon: Icons.wifi_rounded,
              label: 'WiFi',
              isActive: state.wifiEnabled,
              activeColor: AppColors.save,
              onTap: () {
                Haptics.select();
                cubit.toggleWifi();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          state.wifiEnabled
              ? 'Device will connect via Bluetooth and WiFi'
              : 'Tap WiFi to also connect your device to the internet',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.inkSecondary,
          ),
        ),
        const SizedBox(height: 24),

        // ── Device nickname ────────────────────────────────────
        Text(
          'Device Name',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Give your device a name (max 16 characters)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        AppTextField(
          hintText: 'e.g. Home or Upstairs',
          controller: _nicknameController,
          maxLength: 16,
          // ASCII-only keeps characters == bytes: the firmware caps the
          // nickname at 16 BYTES and it becomes the BLE advertising
          // name, so multi-byte characters would be refused on-device.
          // (A pre-existing name outside this set still validates by
          // byte length — the filter only constrains new typing.)
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_-]')),
          ],
          onChanged: cubit.setDeviceNickname,
        ),
        if (state.deviceNickname.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Will advertise as "GeyserSwitch-${state.deviceNickname}"',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: 20),

        // ── WiFi fields (only if enabled) ──────────────────────
        if (state.wifiEnabled) ...[
          Text(
            'WiFi Details',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          if (state.currentSsid != null)
            Text(
              'Auto-detected from your phone — confirm or change',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          AppTextField(
            label: 'Network Name (SSID)',
            hintText: 'Your WiFi network name',
            controller: _ssidController,
            // WiFi spec / firmware buffer: 32 bytes (s_ssid[33]).
            maxLength: 32,
            onChanged: cubit.setSsid,
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Password',
            hintText: state.initialWifiEnabled
                ? '******'
                : 'WiFi password (8–63 characters)',
            obscureText: true,
            controller: _passwordController,
            // WPA2 passphrase bounds; firmware buffer s_pass[65].
            maxLength: 63,
            onChanged: cubit.setWifiPassword,
          ),
          const SizedBox(height: 20),
        ],

        // ── Summary ────────────────────────────────────────────
        _SummaryCard(state: state),
        const SizedBox(height: 24),

        // ── Submit button ──────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: state.canSubmit
                ? () {
                    Haptics.commit();
                    cubit.submit();
                  }
                : null,
            child: Text(state.isAlreadyProvisioned
                ? 'Update Configuration'
                : state.wifiEnabled
                    ? 'Configure Device'
                    : 'Configure Device (BLE Only)'),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Connection chip ──────────────────────────────────────────────────

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // "Active is inset": an engaged chip is carved into the surface with
    // an accent wash; inactive is a flat raised pill — the app-wide
    // neu selection grammar.
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 18,
          color: isActive ? activeColor : AppColors.muted,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isActive ? activeColor : AppColors.muted,
          ),
        ),
      ],
    );

    return GestureDetector(
      onTap: onTap,
      child: isActive
          ? NeuInset(
              borderRadius: 24,
              tint: activeColor.withValues(alpha: 0.14),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: content,
            )
          : Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.neuBase,
                borderRadius: BorderRadius.circular(24),
                boxShadow: neuRaisedShadows(distance: 2, blur: 6),
              ),
              child: content,
            ),
    );
  }
}

// ── Summary card ─────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state});

  final ProvisioningState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: neuRaisedShadows(distance: 3, blur: 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Data to be sent:',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _SummaryRow(
            icon: Icons.badge_outlined,
            label: 'Device Name',
            value: state.deviceNickname.isEmpty
                ? '—'
                : 'GeyserSwitch-${state.deviceNickname}',
          ),
          _SummaryRow(
            icon: Icons.person_outline,
            label: 'User ID',
            value: state.firebaseUid != null
                ? '${state.firebaseUid!.substring(0, 8)}...'
                : '—',
          ),
          _SummaryRow(
            icon: Icons.bluetooth,
            label: 'Bluetooth',
            value: 'Connected',
            valueColor: Colors.green,
          ),
          if (state.wifiEnabled) ...[
            _SummaryRow(
              icon: Icons.wifi,
              label: 'WiFi SSID',
              value: state.ssid.isEmpty ? '—' : state.ssid,
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor ?? theme.colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// ── STEP 2: In Progress ──────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.state});

  final ProvisioningState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        const SizedBox(height: 40),
        const SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: 24),
        Text(
          'Configuring your GeyserSwitch',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          state.statusLabel,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),

        // Progress steps — sublabels mirror the device's status LED so
        // the user can watch the phone and the unit agree
        // (LED_STATUS_SPEC.md).
        _ProgressStep(
          label: 'Device name set',
          sublabel: 'the light on your GeyserSwitch is blue while '
              'connected to your phone',
          isDone: state.deviceStatus != ProvisioningStatus.idle,
        ),
        if (state.wifiEnabled) ...[
          _ProgressStep(
            label: 'Connecting to WiFi',
            sublabel: 'the light blinks green while it joins your network',
            isDone: state.deviceStatus == ProvisioningStatus.wifiOk ||
                state.deviceStatus == ProvisioningStatus.complete,
            isActive: state.deviceStatus == ProvisioningStatus.connecting,
            isFailed: state.deviceStatus == ProvisioningStatus.wifiFail,
          ),
        ],
        _ProgressStep(
          label: 'Finalizing',
          isDone: state.deviceStatus.isSuccess,
          isActive: state.deviceStatus == ProvisioningStatus.wifiOk,
        ),
      ],
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.label,
    this.sublabel,
    this.isDone = false,
    this.isActive = false,
    this.isFailed = false,
  });

  final String label;

  /// Optional LED-mirroring hint shown under the label while the step
  /// is pending/active (hidden once done — the moment has passed).
  final String? sublabel;
  final bool isDone;
  final bool isActive;
  final bool isFailed;

  @override
  Widget build(BuildContext context) {
    final engaged = isDone || isActive || isFailed;

    // Neu step-dot: filled disc for done/active/failed, inset socket for
    // still-to-come.
    final Widget dot;
    if (engaged) {
      final color = isFailed
          ? AppColors.critical
          : isDone
              ? AppColors.primary
              : AppColors.warning;
      dot = Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: Icon(
          isFailed
              ? Icons.close_rounded
              : isDone
                  ? Icons.check_rounded
                  : Icons.sync_rounded,
          size: 14,
          color: Colors.white,
        ),
      );
    } else {
      dot = const NeuInset(
        borderRadius: 11,
        padding: EdgeInsets.zero,
        child: SizedBox(width: 22, height: 22),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dot,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: engaged ? AppColors.ink : AppColors.muted,
                    fontWeight:
                        isDone || isActive ? FontWeight.w600 : null,
                  ),
                ),
                if (sublabel != null && !isDone) ...[
                  const SizedBox(height: 1),
                  Text(
                    sublabel!,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// ── STEP 3: Result ───────────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════

class _ResultView extends StatelessWidget {
  const _ResultView({required this.state});

  final ProvisioningState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = state.isSuccess;

    return Column(
      children: [
        const SizedBox(height: 40),
        Icon(
          success ? Icons.check_circle_rounded : Icons.error_rounded,
          size: 72,
          color: success ? AppColors.save : AppColors.critical,
        ),
        const SizedBox(height: 20),
        Text(
          success ? 'All Set!' : 'Setup Failed',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: success ? AppColors.save : AppColors.critical,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          success
              ? 'Your GeyserSwitch-${state.deviceNickname} is configured and ready to use.'
              : state.errorMessage ?? state.statusLabel,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (success && state.wifiEnabled) ...[
          const SizedBox(height: 8),
          Text(
            'Connected to "${state.ssid}"',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.save,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        if (success && state.remoteSetupFailed) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: neuRaisedShadows(distance: 3, blur: 8),
              border: const Border(
                left: BorderSide(color: AppColors.warning, width: 3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 19, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Remote control setup failed. WiFi control '
                    'will not work until re-provisioned.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 32),

        // ── Action buttons ─────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(success),
            child: Text(success ? 'Done' : 'Close'),
          ),
        ),
        if (!success) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: () =>
                  context.read<ProvisioningCubit>().retry(),
              child: const Text('Try Again'),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
