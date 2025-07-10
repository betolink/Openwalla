import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:luci_mobile/config/app_config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _ipController = TextEditingController();
  final _usernameController = TextEditingController(text: 'root');
  final _passwordController = TextEditingController();
  bool _useHttps = false;
  bool _isCheckingAutoLogin = true;
  bool _passwordVisible = false;
  late AnimationController _logoAnimController;
  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
    _logoAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _logoAnimController.forward();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _logoAnimController.dispose();
    super.dispose();
  }

  Future<void> _tryAutoLogin() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final success = await appState.tryAutoLogin();
    if (success && mounted) {
      Navigator.of(context).pushReplacementNamed('/');
    } else {
      if (mounted) {
        setState(() {
          _isCheckingAutoLogin = false;
        });
      }
    }
  }

  Future<void> _connect() async {
    if (_formKey.currentState!.validate()) {
      final appState = Provider.of<AppState>(context, listen: false);
      final ip = _ipController.text;
      final user = _usernameController.text;
      final pass = _passwordController.text;
      final useHttps = _useHttps;
      final success = await appState.login(
        ip,
        user,
        pass,
        useHttps,
        fromRouter: false,
      );

      if (success && mounted) {
        Navigator.of(context).pushReplacementNamed('/');
      }
    }
  }

  Future<void> _openGitHubIssues() async {
    final url = AppConfig.githubIssuesUrl;
    final success = await launchUrlString(url, mode: LaunchMode.externalApplication);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not open GitHub issues'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAutoLogin) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // Modern gradient background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary.withValues(alpha: 0.18),
                  colorScheme.primaryContainer.withValues(alpha: 0.22),
                  colorScheme.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 32),
                        Text('LuCI Mobile', style: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Connect to your OpenWrt router', style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text('Fast. Secure. Open Source.', style: textTheme.bodySmall?.copyWith(color: colorScheme.primary)),
                        const SizedBox(height: 24),
                        // Glassmorphism card
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Card(
                              elevation: 8,
                              color: colorScheme.surface.withValues(alpha: 0.85),
                              shadowColor: colorScheme.primary.withValues(alpha: 0.10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.10)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
                                child: Form(
                                  key: _formKey,
                                  child: Consumer<AppState>(
                                    builder: (context, appState, child) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Tooltip(
                                            message: 'Enter the IP address or hostname of your router',
                                            child: TextFormField(
                                              controller: _ipController,
                                              autofocus: true,
                                              autofillHints: const [AutofillHints.url, AutofillHints.username],
                                              decoration: const InputDecoration(
                                                labelText: 'IP Address or Hostname',
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(Icons.router_outlined),
                                                helperText: 'e.g. 192.168.1.1 or myrouter.local',
                                              ),
                                              textInputAction: TextInputAction.next,
                                              validator: (value) {
                                                if (value == null || value.isEmpty) {
                                                  return 'Please enter the router address';
                                                }
                                                return null;
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Tooltip(
                                            message: 'Enter your router username',
                                            child: TextFormField(
                                              controller: _usernameController,
                                              autofillHints: const [AutofillHints.username],
                                              decoration: const InputDecoration(
                                                labelText: 'Username',
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(Icons.person_outline),
                                                helperText: 'Default is usually root',
                                              ),
                                              textInputAction: TextInputAction.next,
                                              validator: (value) {
                                                if (value == null || value.isEmpty) {
                                                  return 'Please enter the username';
                                                }
                                                return null;
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Tooltip(
                                            message: 'Enter your router password',
                                            child: TextFormField(
                                              controller: _passwordController,
                                              obscureText: !_passwordVisible,
                                              autofillHints: const [AutofillHints.password],
                                              decoration: InputDecoration(
                                                labelText: 'Password',
                                                border: const OutlineInputBorder(),
                                                prefixIcon: const Icon(Icons.lock_outline),
                                                helperText: 'Your router password',
                                                suffixIcon: IconButton(
                                                  icon: Icon(_passwordVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                                  onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                                                  tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                                                ),
                                              ),
                                              textInputAction: TextInputAction.done,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Icon(Icons.security_outlined, color: colorScheme.onSurfaceVariant),
                                              const SizedBox(width: 12),
                                              Text('Use HTTPS', style: textTheme.titleMedium),
                                              const Spacer(),
                                              Switch(
                                                value: _useHttps,
                                                onChanged: appState.isLoading ? null : (value) => setState(() => _useHttps = value),
                                              ),
                                            ],
                                          ),
                                          AnimatedSwitcher(
                                            duration: const Duration(milliseconds: 300),
                                            child: appState.errorMessage != null
                                                ? Padding(
                                                    key: const ValueKey('error'),
                                                    padding: const EdgeInsets.only(top: 12.0),
                                                    child: Container(
                                                      padding: const EdgeInsets.all(10),
                                                      decoration: BoxDecoration(
                                                        color: colorScheme.errorContainer.withValues(alpha: 1),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
                                                          const SizedBox(width: 12),
                                                          Expanded(
                                                            child: Text(
                                                              appState.errorMessage!,
                                                              style: textTheme.bodyMedium?.copyWith(color: colorScheme.onErrorContainer),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  )
                                                : const SizedBox.shrink(),
                                          ),
                                          const SizedBox(height: 16),
                                          TweenAnimationBuilder<double>(
                                            duration: const Duration(milliseconds: 100),
                                            tween: Tween<double>(begin: 1, end: appState.isLoading ? 0.98 : 1),
                                            builder: (context, scale, child) {
                                              return Transform.scale(
                                                scale: scale,
                                                child: child,
                                              );
                                            },
                                            child: SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton(
                                                onPressed: appState.isLoading ? null : _connect,
                                                style: ElevatedButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(14),
                                                  ),
                                                  elevation: 4,
                                                  backgroundColor: colorScheme.primary,
                                                  foregroundColor: colorScheme.onPrimary,
                                                ),
                                                child: appState.isLoading
                                                    ? const SizedBox(
                                                        height: 26,
                                                        width: 26,
                                                        child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                                                      )
                                                    : Row(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: const [
                                                          Icon(Icons.login),
                                                          SizedBox(width: 12),
                                                          Text('Connect'),
                                                        ],
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Tooltip(
                          message: 'Open GitHub issues for support',
                          child: TextButton(
                            onPressed: _openGitHubIssues,
                            style: TextButton.styleFrom(
                              foregroundColor: colorScheme.primary,
                            ),
                            child: const Text('Need help?'),
                          ),
                        ),
                        FutureBuilder<PackageInfo>(
                          future: PackageInfo.fromPlatform(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const SizedBox.shrink();
                            final info = snapshot.data!;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                'Version ${info.version}',
                                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

