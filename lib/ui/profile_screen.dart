import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import 'widgets/common.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.state,
    required this.themeMode,
    required this.onThemeChanged,
  });

  final AppState state;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need your credentials to sign back in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.danger,
              minimumSize: const Size(90, 44),
            ),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await state.logout();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final employee = state.employee;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.gutter,
          8,
          AppTheme.gutter,
          32,
        ),
        children: [
          SectionCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: scheme.primary.withValues(alpha: 0.14),
                  child: Icon(
                    Icons.person_rounded,
                    size: 30,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee?.name ?? '-',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        employee == null
                            ? ''
                            : '${employee.designation} - ${employee.department}',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      StatusPill(
                        text: 'ID ${employee?.id ?? '-'}',
                        color: scheme.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                _ThemeTile(value: themeMode, onChanged: onThemeChanged),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: AppTheme.danger,
                  ),
                  title: const Text(
                    'Sign out',
                    style: TextStyle(color: AppTheme.danger),
                  ),
                  onTap: () => _confirmLogout(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Sanmarg HRMS - v2.0.0',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.dark_mode_outlined),
      title: const Text('Appearance'),
      trailing: SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode)),
          ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto)),
          ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode)),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}
