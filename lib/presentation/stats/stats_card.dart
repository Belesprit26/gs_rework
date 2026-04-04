import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'device_stats_cubit.dart';

class StatsCard extends StatelessWidget {
  const StatsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DeviceStatsCubit, DeviceStatsState>(
      builder: (context, state) {
        if (!state.hasData) return const SizedBox.shrink();

        final theme = Theme.of(context);

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Today's Usage",
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),

                _StatRow(
                  icon: Icons.timer_outlined,
                  label: 'Runtime',
                  value: _formatRuntime(state.stats.runtimeSeconds),
                  trailing: '${state.stats.cycleCount} '
                      '${state.stats.cycleCount == 1 ? 'cycle' : 'cycles'}',
                ),
                const SizedBox(height: 10),
                _StatRow(
                  icon: Icons.bolt_outlined,
                  label: 'Energy used',
                  value: '${state.actualKwh.toStringAsFixed(1)} kWh',
                ),
                const SizedBox(height: 10),
                _StatRow(
                  icon: Icons.payments_outlined,
                  label: 'Cost',
                  value: 'R${state.actualCost.toStringAsFixed(2)}',
                ),

                if (state.savedKwh > 0) ...[
                  const Divider(height: 24),
                  _StatRow(
                    icon: Icons.eco_outlined,
                    iconColor: Colors.green,
                    label: 'Saved vs uncontrolled',
                    value: '${state.savedKwh.toStringAsFixed(1)} kWh '
                        '(${state.savedPercent.toStringAsFixed(0)}%)',
                    valueColor: Colors.green.shade700,
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 32),
                    child: Text(
                      'R${state.savedCost.toStringAsFixed(2)} saved',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 32),
                    child: Text(
                      'Based on the SA national average for a '
                      '${state.config.tankSize}L geyser running 24/7 '
                      'without a timer '
                      '(~${state.baselineKwh.toStringAsFixed(0)} kWh/day). '
                      'Adjust your setup in Settings.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],

                if (state.lastBoot != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.power_settings_new,
                          size: 16, color: Colors.grey.shade400),
                      const SizedBox(width: 8),
                      Text(
                        'Device booted ${_timeAgo(state.lastBoot!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static String _formatRuntime(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    final days = diff.inDays;
    if (days == 1) return 'yesterday';
    return '$days days ago';
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.iconColor,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? trailing;
  final Color? iconColor;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor ?? Colors.grey.shade600),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade700,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          Text(
            trailing!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade500,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}
