import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/debug/debug_log.dart';
import '../../data/local/prefs_manager.dart';
import '../../di/locator.dart';
import '../../domain/geyser/repositories/rtdb_repository.dart';
import '../shared/widgets/neu/neu.dart';
import '../stats/device_stats_cubit.dart';
import '../theme/app_colors.dart';

/// The Sensors declaration sheet (UX polish E2) — what the user says is
/// physically installed on THIS unit. One surface, two entrances: the
/// Settings "Sensors" row and the provisioning success screen's
/// "Set up your sensors" link.
///
/// Storage: RTDB `set/$did` keys `cs`/`ls` are the cross-phone authority
/// (firmware-ready — unknown keys are ignored on-device today, see
/// APP_FIRMWARE_CONTRACT.md); [PrefsManager] mirrors them locally so
/// BLE-only installs and offline reads work. Temperature has no toggle —
/// it ships in every package, and a broken probe is handled dynamically
/// by the firmware's sensor-fail machinery, not declared here.
Future<void> showSensorsSheet(BuildContext context,
    {required String deviceId}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.paper,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _SensorsSheetBody(deviceId: deviceId),
  );
}

class _SensorsSheetBody extends StatefulWidget {
  const _SensorsSheetBody({required this.deviceId});

  final String deviceId;

  @override
  State<_SensorsSheetBody> createState() => _SensorsSheetBodyState();
}

class _SensorsSheetBodyState extends State<_SensorsSheetBody> {
  final _prefs = getIt<PrefsManager>();

  late bool _current = _prefs.hasCurrentSensor(widget.deviceId);
  late bool _leak = _prefs.hasLeakSensor(widget.deviceId);

  @override
  void initState() {
    super.initState();
    _refreshFromCloud();
  }

  /// RTDB is the cross-phone authority — on open, adopt its values if
  /// another phone changed them. Fire-and-forget; offline just keeps the
  /// local mirror.
  Future<void> _refreshFromCloud() async {
    try {
      final settings =
          await getIt<RtdbRepository>().readSettings(widget.deviceId);
      if (!mounted) return;
      if (settings.currentSensor != _current ||
          settings.leakSensor != _leak) {
        setState(() {
          _current = settings.currentSensor;
          _leak = settings.leakSensor;
        });
        await _prefs.setHasCurrentSensor(widget.deviceId, _current);
        await _prefs.setHasLeakSensor(widget.deviceId, _leak);
      }
    } catch (e) {
      debugLog('Sensors', 'Cloud refresh skipped: $e');
    }
  }

  Future<void> _setCurrent(bool v) async {
    setState(() => _current = v);
    await _prefs.setHasCurrentSensor(widget.deviceId, v);
    // Re-select the energy seam immediately.
    if (mounted) context.read<DeviceStatsCubit>().refreshSensorFlag();
    _syncCloud('cs', v);
  }

  Future<void> _setLeak(bool v) async {
    setState(() => _leak = v);
    await _prefs.setHasLeakSensor(widget.deviceId, v);
    _syncCloud('ls', v);
  }

  void _syncCloud(String key, bool v) {
    getIt<RtdbRepository>()
        .writeSettings(widget.deviceId, {key: v}).catchError((Object e) {
      // Offline is fine — the local mirror holds; next write syncs.
      debugLog('Sensors', 'Cloud sync deferred ($key): $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sensors',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              "What's installed on this unit — it decides what the app "
              'tracks, measures and displays.',
              style: TextStyle(fontSize: 13, color: AppColors.inkSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: neuRaisedShadows(distance: 3, blur: 8),
              ),
              child: Column(
                children: [
                  const _SensorRow(
                    icon: Icons.thermostat_rounded,
                    title: 'Temperature sensor',
                    description:
                        'Included with every GeyserSwitch — drives the '
                        'dial, limits and auto-reheat.',
                    lockedLabel: 'Included',
                  ),
                  const Divider(
                      height: 1, indent: 14, color: AppColors.hairline),
                  _SensorRow(
                    icon: Icons.water_drop_outlined,
                    title: 'Leak sensor',
                    description: 'Cuts power and alerts you the moment '
                        'water is detected near the geyser.',
                    value: _leak,
                    onChanged: _setLeak,
                  ),
                  const Divider(
                      height: 1, indent: 14, color: AppColors.hairline),
                  _SensorRow(
                    icon: Icons.bolt_rounded,
                    title: 'Current sensor',
                    description:
                        'Measures real power use instead of estimating it.',
                    value: _current,
                    onChanged: _setCurrent,
                    note: _current
                        ? 'Measured readings arrive with a firmware '
                            'update — estimates are used until then.'
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: NeuButton(
                label: 'Done',
                primary: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SensorRow extends StatelessWidget {
  const _SensorRow({
    required this.icon,
    required this.title,
    required this.description,
    this.value,
    this.onChanged,
    this.lockedLabel,
    this.note,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool? value;
  final ValueChanged<bool>? onChanged;

  /// Non-null renders an inset "Included" chip instead of a switch.
  final String? lockedLabel;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      description,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.inkSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (lockedLabel != null)
                NeuInset(
                  borderRadius: 10,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  tint: AppColors.primary.withValues(alpha: 0.10),
                  child: Text(
                    lockedLabel!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                )
              else
                NeuSwitch(value: value!, onChanged: onChanged),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 14, color: AppColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    note!,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
