import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/dashboard_preferences.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/widgets/luci_animation_system.dart';
import 'package:luci_mobile/widgets/luci_utility_components.dart';

class DashboardCustomizationScreen extends ConsumerStatefulWidget {
  const DashboardCustomizationScreen({super.key});

  @override
  ConsumerState<DashboardCustomizationScreen> createState() =>
      _DashboardCustomizationScreenState();
}

class _DashboardCustomizationScreenState
    extends ConsumerState<DashboardCustomizationScreen> 
    with SingleTickerProviderStateMixin {
  late DashboardPreferences _preferences;
  bool _isLoading = true;
  String? _errorMessage;
  final Set<String> _availableWirelessInterfaces = {};
  final Set<String> _availableWiredInterfaces = {};
  final List<String> _allInterfaces = [];
  bool _hasChanges = false;
  late AnimationController _fabAnimationController;
  late Animation<double> _fabScaleAnimation;
  // Controller not used; rely on initialValue with keyed widget
  static const String _allInterfacesOption = '__ALL__';

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      duration: LuciAnimations.fast,
      vsync: this,
    );
    _fabScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fabAnimationController,
      curve: LuciAnimations.easeOut,
    ));
    _loadPreferences();
  }

  @override
  void dispose() {
    _fabAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      final appState = ref.read(appStateProvider);
      
      // Fetch dashboard data if not available
      if (appState.dashboardData == null) {
        await appState.fetchDashboardData();
      }
      
      // Check if we have data
      if (appState.dashboardData == null) {
        setState(() {
          _errorMessage = 'Unable to load dashboard data. Please check your connection.';
          _isLoading = false;
        });
        return;
      }
      
      // Load current preferences
      _preferences = appState.dashboardPreferences;
      
      // Extract available interfaces
      _extractAvailableInterfaces(appState.dashboardData);

      // No controller needed; handled by keyed DropdownButtonFormField

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load settings: $e';
        _isLoading = false;
      });
    }
  }

  void _extractAvailableInterfaces(Map<String, dynamic>? dashboardData) {
    if (dashboardData == null) return;

    // Extract wireless interfaces
    final wirelessRadios = dashboardData['wireless'] as Map<String, dynamic>?;
    if (wirelessRadios != null) {
      wirelessRadios.forEach((radioName, radioData) {
        final interfaces = radioData['interfaces'] as List<dynamic>?;
        if (interfaces != null) {
          for (var interface in interfaces) {
            final config = interface['config'] ?? {};
            final iwinfo = interface['iwinfo'] ?? {};
            final ssid = iwinfo['ssid'] ?? config['ssid'];
            final deviceName = config['device'] ?? radioName;
            
            if (ssid != null && ssid.toString().isNotEmpty) {
              final interfaceId = '$ssid ($deviceName)';
              _availableWirelessInterfaces.add(interfaceId);
              _allInterfaces.add(interfaceId);
            }
          }
        }
      });
    }

    // Extract ALL interfaces (except loopback)
    final interfaces = dashboardData['interfaceDump']?['interface'] as List<dynamic>?;
    if (interfaces != null) {
      for (var item in interfaces) {
        final interface = item as Map<String, dynamic>;
        final name = interface['interface'] as String? ?? '';
        
        // Include all interfaces except loopback
        if (name.isNotEmpty && name != 'loopback' && name != 'lo') {
          _availableWiredInterfaces.add(name);
          _allInterfaces.add(name);
        }
      }
    }

    // Sort interfaces for better UX
    _allInterfaces.sort();
  }

  void _onPreferenceChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
      _fabAnimationController.forward();
    }
  }

  Widget _buildSection({
    required String title,
    required String subtitle,
    required List<Widget> children,
    IconData? icon,
    bool initiallyExpanded = false,
  }) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(
        horizontal: LuciSpacing.md,
        vertical: LuciSpacing.sm,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: LuciCardStyles.standardRadius,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          leading: icon != null 
              ? Icon(icon, color: Theme.of(context).colorScheme.primary)
              : null,
          title: Text(
            title,
            style: LuciTextStyles.cardTitle(context),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              subtitle,
              style: LuciTextStyles.cardSubtitle(context),
            ),
          ),
          initiallyExpanded: initiallyExpanded,
          shape: RoundedRectangleBorder(
            borderRadius: LuciCardStyles.standardRadius,
          ),
          childrenPadding: EdgeInsets.symmetric(
            horizontal: LuciSpacing.md,
            vertical: LuciSpacing.sm,
          ),
          children: children,
        ),
      ),
    );
  }

  Widget _buildThroughputSection() {
    final interfaces = _allInterfaces.toList();

    return _buildSection(
      title: 'Throughput Monitoring',
      subtitle: 'Configure which interfaces to monitor',
      icon: Icons.speed,
      initiallyExpanded: true,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(
            _preferences.showAllThroughput
                ? _allInterfacesOption
                : (_preferences.primaryThroughputInterface ?? _allInterfacesOption),
          ),
          initialValue: _preferences.showAllThroughput
              ? _allInterfacesOption
              : (_preferences.primaryThroughputInterface ?? _allInterfacesOption),
          decoration: InputDecoration(
            labelText: 'Throughput Source',
            prefixIcon: Icon(
              _preferences.showAllThroughput ? Icons.all_inclusive : Icons.lan,
              color: Theme.of(context).colorScheme.primary,
            ),
            border: OutlineInputBorder(
              borderRadius: LuciCardStyles.standardRadius,
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ),
          isExpanded: true,
          dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
          style: LuciTextStyles.detailValue(context),
          items: [
            DropdownMenuItem(
              value: _allInterfacesOption,
              child: Row(
                children: [
                  Icon(
                    Icons.all_inclusive,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  SizedBox(width: LuciSpacing.sm),
                  const Expanded(
                    child: Text(
                      'All Interfaces',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            ...interfaces.map((iface) {
              return DropdownMenuItem(
                value: iface,
                child: Row(
                  children: [
                    Icon(
                      _getInterfaceIcon(iface),
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    SizedBox(width: LuciSpacing.sm),
                    Expanded(
                      child: Text(
                        iface,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          onChanged: (value) {
            setState(() {
              if (value == _allInterfacesOption) {
                _preferences = _preferences.copyWith(
                  showAllThroughput: true,
                  primaryThroughputInterface: null,
                );
              } else {
                _preferences = _preferences.copyWith(
                  showAllThroughput: false,
                  primaryThroughputInterface: value,
                );
              }
            });
            _onPreferenceChanged();
          },
        ),
      ],
    );
  }

  Widget _buildWirelessInterfacesSection() {
    if (_availableWirelessInterfaces.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedInterfaces = _availableWirelessInterfaces.toList()..sort();

    return _buildSection(
      title: 'Wireless Networks',
      subtitle: 'Choose which wireless networks to display',
      icon: Icons.wifi,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: Text(
                  'Show All Networks',
                  style: LuciTextStyles.detailValue(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                value: _preferences.enabledWirelessInterfaces.isEmpty,
                onChanged: (value) {
                  setState(() {
                    if (value) {
                      _preferences = _preferences.copyWith(
                        enabledWirelessInterfaces: {},
                      );
                    } else {
                      _preferences = _preferences.copyWith(
                        enabledWirelessInterfaces: Set.from(_availableWirelessInterfaces),
                      );
                    }
                  });
                  _onPreferenceChanged();
                },
                activeTrackColor: Theme.of(context).colorScheme.primary,
                activeThumbColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ],
          ),
        ),
        if (_preferences.enabledWirelessInterfaces.isNotEmpty) ...[
          SizedBox(height: LuciSpacing.sm),
          ...sortedInterfaces.map((interface) {
            final isEnabled = _preferences.enabledWirelessInterfaces.contains(interface);
            
            return Padding(
              padding: EdgeInsets.symmetric(vertical: LuciSpacing.xs),
              child: CheckboxListTile(
                title: Text(
                  interface,
                  style: LuciTextStyles.detailValue(context),
                ),
                secondary: Icon(
                  Icons.wifi,
                  size: 20,
                  color: isEnabled 
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                value: isEnabled,
                onChanged: (value) {
                  setState(() {
                    final newSet = Set<String>.from(_preferences.enabledWirelessInterfaces);
                    if (value ?? false) {
                      newSet.add(interface);
                    } else {
                      newSet.remove(interface);
                    }
                    _preferences = _preferences.copyWith(
                      enabledWirelessInterfaces: newSet,
                    );
                  });
                  _onPreferenceChanged();
                },
                activeColor: Theme.of(context).colorScheme.primary,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildWiredInterfacesSection() {
    if (_availableWiredInterfaces.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedInterfaces = _availableWiredInterfaces.toList()..sort();

    return _buildSection(
      title: 'Network Interfaces',
      subtitle: 'Choose which wired/VPN interfaces to display',
      icon: Icons.cable,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: Text(
                  'Show All Interfaces',
                  style: LuciTextStyles.detailValue(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                value: _preferences.enabledWiredInterfaces.isEmpty,
                onChanged: (value) {
                  setState(() {
                    if (value) {
                      _preferences = _preferences.copyWith(
                        enabledWiredInterfaces: {},
                      );
                    } else {
                      _preferences = _preferences.copyWith(
                        enabledWiredInterfaces: Set.from(_availableWiredInterfaces),
                      );
                    }
                  });
                  _onPreferenceChanged();
                },
                activeTrackColor: Theme.of(context).colorScheme.primary,
                activeThumbColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ],
          ),
        ),
        if (_preferences.enabledWiredInterfaces.isNotEmpty) ...[
          SizedBox(height: LuciSpacing.sm),
          ...sortedInterfaces.map((interface) {
            final isEnabled = _preferences.enabledWiredInterfaces.contains(interface);
            final description = _getInterfaceDescription(interface);
            
            return Padding(
              padding: EdgeInsets.symmetric(vertical: LuciSpacing.xs),
              child: CheckboxListTile(
                title: Text(
                  interface.toUpperCase(),
                  style: LuciTextStyles.detailValue(context),
                ),
                subtitle: description,
                secondary: Icon(
                  _getInterfaceIcon(interface),
                  size: 20,
                  color: isEnabled 
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                value: isEnabled,
                onChanged: (value) {
                  setState(() {
                    final newSet = Set<String>.from(_preferences.enabledWiredInterfaces);
                    if (value ?? false) {
                      newSet.add(interface);
                    } else {
                      newSet.remove(interface);
                    }
                    _preferences = _preferences.copyWith(
                      enabledWiredInterfaces: newSet,
                    );
                  });
                  _onPreferenceChanged();
                },
                activeColor: Theme.of(context).colorScheme.primary,
                controlAffinity: ListTileControlAffinity.leading,
                dense: description != null,
              ),
            );
          }),
        ],
      ],
    );
  }

  IconData _getInterfaceIcon(String interface) {
    final lower = interface.toLowerCase();
    if (lower.contains('wan')) return Icons.public;
    if (lower.contains('lan')) return Icons.router;
    if (lower.contains('iot')) return Icons.sensors;
    if (lower.contains('guest')) return Icons.people;
    if (lower.contains('dmz')) return Icons.security;
    if (lower.contains('wireguard') || lower.contains('vpn') || lower.startsWith('wg')) return Icons.vpn_key;
    if (lower.contains('pppoe')) return Icons.settings_ethernet;
    if (lower.contains('wifi') || lower.contains('wlan')) return Icons.wifi;
    if (lower.contains('docker')) return Icons.computer;
    if (lower.contains('bridge') || lower.startsWith('br-')) return Icons.hub;
    if (lower.contains('vlan')) return Icons.layers;
    if (lower.startsWith('eth')) return Icons.cable;
    return Icons.lan;
  }

  Widget? _getInterfaceDescription(String interface) {
    final lower = interface.toLowerCase();
    if (lower.startsWith('wan')) {
      return Text('Wide Area Network', style: LuciTextStyles.cardSubtitle(context));
    } else if (lower.startsWith('lan')) {
      return Text('Local Area Network', style: LuciTextStyles.cardSubtitle(context));
    } else if (lower.contains('iot')) {
      return Text('IoT Network', style: LuciTextStyles.cardSubtitle(context));
    } else if (lower.contains('guest')) {
      return Text('Guest Network', style: LuciTextStyles.cardSubtitle(context));
    } else if (lower.contains('wireguard') || lower.startsWith('wg')) {
      return Text('WireGuard VPN', style: LuciTextStyles.cardSubtitle(context));
    } else if (lower.contains('openvpn')) {
      return Text('OpenVPN', style: LuciTextStyles.cardSubtitle(context));
    } else if (lower.contains('pppoe')) {
      return Text('PPPoE Connection', style: LuciTextStyles.cardSubtitle(context));
    } else if (lower.contains('dmz')) {
      return Text('DMZ Network', style: LuciTextStyles.cardSubtitle(context));
    } else if (lower.contains('docker')) {
      return Text('Docker Network', style: LuciTextStyles.cardSubtitle(context));
    } else if (lower.contains('bridge') || lower.startsWith('br-')) {
      return Text('Network Bridge', style: LuciTextStyles.cardSubtitle(context));
    } else if (lower.contains('vlan')) {
      return Text('VLAN Interface', style: LuciTextStyles.cardSubtitle(context));
    } else if (lower.startsWith('eth')) {
      return Text('Ethernet Interface', style: LuciTextStyles.cardSubtitle(context));
    } else if (lower.startsWith('wlan')) {
      return Text('Wireless Interface', style: LuciTextStyles.cardSubtitle(context));
    }
    return null;
  }

  Future<void> _savePreferences() async {
    final appState = ref.read(appStateProvider);

    try {
      await appState.saveDashboardPreferences(_preferences);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.onPrimary,
                  size: 20,
                ),
                SizedBox(width: LuciSpacing.sm),
                const Text('Dashboard preferences saved'),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: EdgeInsets.symmetric(
              horizontal: LuciSpacing.lg,
              vertical: LuciSpacing.md,
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.onError,
                  size: 20,
                ),
                SizedBox(width: LuciSpacing.sm),
                Expanded(child: Text('Failed to save: $e')),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: EdgeInsets.symmetric(
              horizontal: LuciSpacing.lg,
              vertical: LuciSpacing.md,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        appBar: LuciAppBar(
          title: 'Dashboard Settings',
          showBack: true,
        ),
        body: Center(
          child: LuciLoadingWidget(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: const LuciAppBar(
          title: 'Dashboard Settings',
          showBack: true,
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(LuciSpacing.lg),
            child: LuciErrorDisplay(
              title: 'Unable to Load Settings',
              message: _errorMessage!,
              icon: Icons.error_outline,
              actionLabel: 'Retry',
              onAction: () {
                setState(() {
                  _errorMessage = null;
                  _isLoading = true;
                });
                _loadPreferences();
              },
            ),
          ),
        ),
      );
    }

    final appState = ref.watch(appStateProvider);
    return Scaffold(
      appBar: const LuciAppBar(
        title: 'Dashboard Settings',
        showBack: true,
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: LuciSpacing.sm),
        children: [
          // Router selector for per-router preferences to match app patterns
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: LuciSpacing.md,
              vertical: LuciSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preferences For',
                  style: LuciTextStyles.sectionHeader(context),
                ),
                SizedBox(height: LuciSpacing.xs),
                LuciUtilityComponents.routerSelector(
                  context: context,
                  routers: appState.routers,
                  selectedRouter: appState.selectedRouter,
                  onRouterChanged: (id) async {
                    // Switch router; preferences auto-load per router
                    await appState.selectRouter(id, context: context);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ),
          LuciStaggeredAnimation(
            staggerDelay: const Duration(milliseconds: 50),
            children: [
              _buildThroughputSection(),
              _buildWirelessInterfacesSection(),
              _buildWiredInterfacesSection(),
              SizedBox(height: LuciSpacing.xxl * 2), // Space for FAB
            ],
          ),
        ],
      ),
      floatingActionButton: _hasChanges
          ? ScaleTransition(
              scale: _fabScaleAnimation,
              child: FloatingActionButton.extended(
                onPressed: _savePreferences,
                label: const Text('Save Changes'),
                icon: const Icon(Icons.save),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            )
          : null,
    );
  }
}
