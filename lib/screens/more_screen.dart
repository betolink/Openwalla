import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/screens/login_screen.dart';
import 'package:luci_mobile/screens/settings_screen.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:luci_mobile/config/app_config.dart';
import 'package:luci_mobile/screens/manage_routers_screen.dart';

class LuciSectionHeader extends StatelessWidget {
  final String title;
  const LuciSectionHeader(this.title, {super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _MoreScreenSection extends StatelessWidget {
  final List<Widget> tiles;

  const _MoreScreenSection({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: ListTile.divideTiles(
          context: context,
          tiles: tiles,
        ).toList(),
      ),
    );
  }
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  Future<void> _showLogoutDialog(BuildContext context, AppState appState) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout?'),
          content: const Text('Are you sure you want to logout?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Logout'),
              onPressed: () {
                appState.logout();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (Route<dynamic> route) => false,
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showRebootDialog(BuildContext context, AppState appState) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Reboot Router?'),
          content: const Text('Are you sure you want to reboot the router?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Reboot'),
              onPressed: () async {
                Navigator.of(context).pop();
                final success = await appState.reboot();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Reboot command sent successfully.' : 'Failed to send reboot command.'),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAboutDialog(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.router, size: 32),
              const SizedBox(width: 12),
              const Text('LuCI Mobile'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version ${info.version}'),
              const SizedBox(height: 16),
              const Text('A mobile client for OpenWrt routers.'),
              const SizedBox(height: 16),
              const Text('Open source and free to use.'),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final url = AppConfig.githubRepositoryUrl;
                  final success = await launchUrlString(url, mode: LaunchMode.externalApplication);
                  if (!success && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Could not open repository'),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                  }
                },
                child: Row(
                  children: [
                    Icon(
                      Icons.link,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'GitHub Repository',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);

    return Scaffold(
      appBar: const LuciAppBar(title: 'More'),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        children: [
          const LuciSectionHeader('Device Management'),
          _MoreScreenSection(
            tiles: [
              _buildMoreTile(
                context,
                icon: Icons.restart_alt,
                iconColor: Theme.of(context).colorScheme.primary,
                title: 'Reboot Router',
                subtitle: 'Perform a system restart',
                onTap: () => _showRebootDialog(context, appState),
              ),
            ],
          ),
          const LuciSectionHeader('Application'),
          _MoreScreenSection(
            tiles: [
              _buildMoreTile(
                context,
                icon: Icons.router,
                iconColor: Theme.of(context).colorScheme.primary,
                title: 'Manage Routers',
                subtitle: 'Edit or remove saved routers',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const ManageRoutersScreen()),
                  );
                },
              ),
              _buildMoreTile(
                context,
                icon: Icons.settings_outlined,
                iconColor: Theme.of(context).colorScheme.primary,
                title: 'Settings',
                subtitle: 'Configure app preferences',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const SettingsScreen()),
                  );
                },
              ),
              _buildMoreTile(
                context,
                icon: Icons.info_outline,
                iconColor: Theme.of(context).colorScheme.secondary,
                title: 'About',
                subtitle: 'App version and information',
                onTap: () => _showAboutDialog(context),
              ),
              _buildMoreTile(
                context,
                icon: Icons.logout,
                iconColor: Theme.of(context).colorScheme.error,
                title: 'Logout',
                subtitle: 'End your session and sign out',
                titleColor: Theme.of(context).colorScheme.error,
                subtitleColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.7),
                onTap: () => _showLogoutDialog(context, appState),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMoreTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool enabled = true,
    Color? titleColor,
    Color? subtitleColor,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Container(
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.all(10),
        child: Icon(icon, color: iconColor, size: 24, semanticLabel: title),
      ),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: titleColor ?? theme.colorScheme.onSurface,
          fontWeight: FontWeight.bold,
        ),
        semanticsLabel: title,
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: subtitleColor ?? theme.colorScheme.onSurfaceVariant,
        ),
        semanticsLabel: subtitle,
      ),
      enabled: enabled,
      onTap: enabled ? onTap : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      hoverColor: theme.colorScheme.primary.withValues(alpha: 0.04),
      splashColor: theme.colorScheme.primary.withValues(alpha: 0.08),
      minVerticalPadding: 16,
      minLeadingWidth: 0,
      visualDensity: VisualDensity.standard,
    );
  }
}
