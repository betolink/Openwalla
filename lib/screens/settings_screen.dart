import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/screens/dashboard_customization_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  
  void _showReviewerModeResetDialog(BuildContext context, WidgetRef ref) {
    final appState = ref.read(appStateProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Reviewer Mode?'),
        content: const Text(
          'This will disable reviewer mode and return to normal authentication. '
          'You will need to log in with real router credentials.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await appState.setReviewerMode(false);
              appState.logout();
              if (context.mounted) {
                unawaited(Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false));
              }
            },
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }
  
  void _showRefreshIntervalDialog(BuildContext context, WidgetRef ref) {
    final appState = ref.read(appStateProvider);
    int selectedInterval = appState.dashboardRefreshInterval;
    
    final intervals = [
      5, 10, 15, 30, 45, 60, 90, 120, 180, 300
    ];
    
    final intervalLabels = {
      5: '5 seconds',
      10: '10 seconds',
      15: '15 seconds',
      30: '30 seconds',
      45: '45 seconds',
      60: '1 minute',
      90: '1.5 minutes',
      120: '2 minutes',
      180: '3 minutes',
      300: '5 minutes',
    };
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dashboard Auto-refresh'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select how often the dashboard should automatically refresh',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ...intervals.map((interval) => RadioListTile<int>(
              title: Text(intervalLabels[interval]!),
              value: interval,
              groupValue: selectedInterval,
              onChanged: (value) {
                Navigator.of(context).pop(value);
              },
              dense: true,
              contentPadding: EdgeInsets.zero,
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ).then((value) {
      if (value != null && value != appState.dashboardRefreshInterval) {
        appState.setDashboardRefreshInterval(value);
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Settings', showBack: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        children: [
          Builder(
            builder: (context) {
              final appState = ref.watch(appStateProvider);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
                    child: Text('Theme', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('System Default'),
                    value: ThemeMode.system,
                    groupValue: appState.themeMode,
                    onChanged: (mode) => appState.setThemeMode(mode!),
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('Light'),
                    value: ThemeMode.light,
                    groupValue: appState.themeMode,
                    onChanged: (mode) => appState.setThemeMode(mode!),
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('Dark'),
                    value: ThemeMode.dark,
                    groupValue: appState.themeMode,
                    onChanged: (mode) => appState.setThemeMode(mode!),
                  ),
                  const Divider(height: 32),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      'Dashboard',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.dashboard_customize),
                    title: const Text('Customize Dashboard'),
                    subtitle: const Text('Choose which interfaces to display'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const DashboardCustomizationScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.timer),
                    title: const Text('Auto-refresh Interval'),
                    subtitle: Text('Refresh every ${appState.dashboardRefreshInterval} seconds'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      _showRefreshIntervalDialog(context, ref);
                    },
                  ),
                  if (appState.reviewerModeEnabled) ...[
                    const Divider(height: 32),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text('Reviewer Mode', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline, color: Colors.orange),
                      title: const Text('Reviewer Mode Active'),
                      subtitle: Text(
                        'Mock data is being used for demonstration',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: FilledButton.icon(
                        onPressed: () => _showReviewerModeResetDialog(context, ref),
                        icon: const Icon(Icons.exit_to_app),
                        label: const Text('Exit Reviewer Mode'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(context).colorScheme.onError,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
