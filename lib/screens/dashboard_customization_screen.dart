import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/dashboard_preferences.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_loading_states.dart';

class DashboardCustomizationScreen extends ConsumerStatefulWidget {
  const DashboardCustomizationScreen({super.key});

  @override
  ConsumerState<DashboardCustomizationScreen> createState() =>
      _DashboardCustomizationScreenState();
}

class _DashboardCustomizationScreenState
    extends ConsumerState<DashboardCustomizationScreen> {
  late DashboardPreferences _preferences;
  bool _isLoading = true;
  final Set<String> _availableWirelessInterfaces = {};
  final Set<String> _availableWiredInterfaces = {};
  final List<String> _allInterfaces = [];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final appState = ref.read(appStateProvider);
    
    // Fetch dashboard data if not available
    if (appState.dashboardData == null) {
      await appState.fetchDashboardData();
    }
    
    // Load current preferences
    _preferences = appState.dashboardPreferences;
    
    // Extract available interfaces
    _extractAvailableInterfaces(appState.dashboardData);
    
    setState(() => _isLoading = false);
  }

  void _extractAvailableInterfaces(Map<String, dynamic>? dashboardData) {
    if (dashboardData == null) return;

    // Extract wireless interfaces (including from UCI config)
    final wirelessRadios = dashboardData['wireless'] as Map<String, dynamic>?;
    final uciWirelessConfig = dashboardData['uciWirelessConfig'];
    final runtimeInterfaces = <String>{};
    
    // Extract runtime wireless interfaces
    if (wirelessRadios != null) {
      wirelessRadios.forEach((radioName, radioData) {
        final interfaces = radioData['interfaces'] as List<dynamic>?;
        if (interfaces != null) {
          for (var interface in interfaces) {
            final config = interface['config'] ?? {};
            final iwinfo = interface['iwinfo'] ?? {};
            final ssid = iwinfo['ssid'] ?? config['ssid'];
            final deviceName = config['device'] ?? radioName;
            final uciName = interface['section'] as String?;
            
            if (uciName != null) {
              runtimeInterfaces.add(uciName);
            }
            
            if (ssid != null && ssid.toString().isNotEmpty) {
              final interfaceId = '$ssid ($deviceName)';
              _availableWirelessInterfaces.add(interfaceId);
              _allInterfaces.add(interfaceId);
            } else {
              // Even interfaces without SSID should be shown
              final interfaceId = deviceName;
              _availableWirelessInterfaces.add(interfaceId);
              _allInterfaces.add(interfaceId);
            }
          }
        }
      });
    }
    
    // Extract UCI-configured wireless interfaces that aren't running
    if (uciWirelessConfig != null) {
      final uciValues = uciWirelessConfig['values'] as Map?;
      if (uciValues != null) {
        uciValues.forEach((key, value) {
          final typedValue = value as Map?;
          if (typedValue?['.type'] == 'wifi-iface' && !runtimeInterfaces.contains(key)) {
            final ssid = typedValue?['ssid'];
            final device = typedValue?['device'];
            if (ssid != null && ssid.toString().isNotEmpty) {
              final interfaceId = '$ssid ($device)';
              _availableWirelessInterfaces.add(interfaceId);
              _allInterfaces.add(interfaceId);
            } else if (device != null) {
              _availableWirelessInterfaces.add(device);
              _allInterfaces.add(device);
            }
          }
        });
      }
    }

    // Extract ALL wired interfaces from interface dump
    final interfaces = dashboardData['interfaceDump']?['interface'] as List<dynamic>?;
    if (interfaces != null) {
      for (var item in interfaces) {
        final interface = item as Map<String, dynamic>;
        final name = interface['interface'] as String? ?? '';
        
        // Include ALL interfaces (not just wan/lan/vpn)
        if (name.isNotEmpty) {
          _availableWiredInterfaces.add(name);
          _allInterfaces.add(name);
        }
      }
    }

    // Sort interfaces for better UX
    _allInterfaces.sort();
  }

  List<String> _getAllInterfaces() {
    return _allInterfaces;
  }

  Widget _buildThroughputSection() {
    // Only show wired interfaces for throughput selection
    final interfaces = _availableWiredInterfaces.toList()..sort();

    return Card(
      margin: const EdgeInsets.all(16),
      child: ExpansionTile(
        title: const Text(
          'Throughput Graph',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Configure which interfaces to monitor'),
        initiallyExpanded: true,
        children: [
          RadioListTile<bool>(
            title: const Text('Show All Interfaces Combined'),
            subtitle: const Text('Display total throughput across all interfaces'),
            value: true,
            groupValue: _preferences.showAllThroughput,
            onChanged: (value) {
              setState(() {
                _preferences = _preferences.copyWith(
                  showAllThroughput: true,
                  primaryThroughputInterface: null,
                );
              });
            },
          ),
          RadioListTile<bool>(
            title: const Text('Show Specific Interface'),
            subtitle: const Text('Monitor throughput for a single interface'),
            value: false,
            groupValue: _preferences.showAllThroughput,
            onChanged: (value) {
              setState(() {
                _preferences = _preferences.copyWith(
                  showAllThroughput: false,
                  primaryThroughputInterface: interfaces.isNotEmpty ? interfaces.first : null,
                );
              });
            },
          ),
          if (!_preferences.showAllThroughput)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: DropdownButtonFormField<String>(
                value: _preferences.primaryThroughputInterface,
                decoration: InputDecoration(
                  labelText: 'Select Interface',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                isExpanded: true,
                items: interfaces.map((iface) {
                  return DropdownMenuItem(
                    value: iface,
                    child: Text(
                      iface,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _preferences = _preferences.copyWith(
                      primaryThroughputInterface: value,
                    );
                  });
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildWirelessInterfacesSection() {
    if (_availableWirelessInterfaces.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        title: const Text(
          'Wireless Interfaces',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Select which wireless networks to display'),
        children: [
          CheckboxListTile(
            title: const Text('Show All'),
            value: _preferences.enabledWirelessInterfaces.isEmpty,
            onChanged: (value) {
              setState(() {
                if (value ?? false) {
                  _preferences = _preferences.copyWith(
                    enabledWirelessInterfaces: {},
                  );
                } else {
                  _preferences = _preferences.copyWith(
                    enabledWirelessInterfaces: Set.from(_availableWirelessInterfaces),
                  );
                }
              });
            },
          ),
          const Divider(height: 1),
          ..._availableWirelessInterfaces.map((interface) {
            final isEnabled = _preferences.enabledWirelessInterfaces.isEmpty ||
                _preferences.enabledWirelessInterfaces.contains(interface);
            
            return CheckboxListTile(
              title: Text(interface),
              value: isEnabled,
              enabled: _preferences.enabledWirelessInterfaces.isNotEmpty,
              onChanged: _preferences.enabledWirelessInterfaces.isEmpty
                  ? null
                  : (value) {
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
                    },
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildWiredInterfacesSection() {
    if (_availableWiredInterfaces.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        title: const Text(
          'Network Interfaces',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Select which network interfaces to display'),
        children: [
          CheckboxListTile(
            title: const Text('Show All'),
            value: _preferences.enabledWiredInterfaces.isEmpty,
            onChanged: (value) {
              setState(() {
                if (value ?? false) {
                  _preferences = _preferences.copyWith(
                    enabledWiredInterfaces: {},
                  );
                } else {
                  _preferences = _preferences.copyWith(
                    enabledWiredInterfaces: Set.from(_availableWiredInterfaces),
                  );
                }
              });
            },
          ),
          const Divider(height: 1),
          ..._availableWiredInterfaces.map((interface) {
            final isEnabled = _preferences.enabledWiredInterfaces.isEmpty ||
                _preferences.enabledWiredInterfaces.contains(interface);
            
            return CheckboxListTile(
              title: Text(interface.toUpperCase()),
              subtitle: _getInterfaceDescription(interface),
              value: isEnabled,
              enabled: _preferences.enabledWiredInterfaces.isNotEmpty,
              onChanged: _preferences.enabledWiredInterfaces.isEmpty
                  ? null
                  : (value) {
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
                    },
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget? _getInterfaceDescription(String interface) {
    final lowerInterface = interface.toLowerCase();
    if (lowerInterface.startsWith('wan')) {
      return const Text('Wide Area Network');
    } else if (lowerInterface.startsWith('lan')) {
      return const Text('Local Area Network');
    } else if (lowerInterface.contains('wireguard') || lowerInterface.startsWith('wg')) {
      return const Text('WireGuard VPN');
    } else if (lowerInterface.contains('openvpn')) {
      return const Text('OpenVPN');
    } else if (lowerInterface.contains('pppoe')) {
      return const Text('PPPoE Connection');
    } else if (lowerInterface.startsWith('br-') || lowerInterface.contains('bridge')) {
      return const Text('Network Bridge');
    } else if (lowerInterface.startsWith('eth')) {
      return const Text('Ethernet Interface');
    } else if (lowerInterface.startsWith('wlan')) {
      return const Text('Wireless Interface');
    } else if (lowerInterface.contains('loopback') || lowerInterface == 'lo') {
      return const Text('Loopback Interface');
    } else if (lowerInterface.contains('docker')) {
      return const Text('Docker Network');
    } else if (lowerInterface.contains('veth')) {
      return const Text('Virtual Ethernet');
    } else if (lowerInterface.contains('tun')) {
      return const Text('Tunnel Interface');
    } else if (lowerInterface.contains('tap')) {
      return const Text('TAP Interface');
    } else if (lowerInterface.contains('vlan')) {
      return const Text('VLAN Interface');
    } else if (lowerInterface.startsWith('usb')) {
      return const Text('USB Network');
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
            content: const Text('Dashboard preferences saved'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save preferences: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
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
          title: 'Dashboard Customization',
          showBack: true,
        ),
        body: Center(
          child: LuciLoadingWidget(),
        ),
      );
    }

    return Scaffold(
      appBar: LuciAppBar(
        title: 'Dashboard Customization',
        showBack: true,
        actions: [
          TextButton(
            onPressed: _savePreferences,
            child: Text(
              'Save',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _buildThroughputSection(),
          _buildWirelessInterfacesSection(),
          _buildWiredInterfacesSection(),
          const SizedBox(height: 80), // Space for FAB
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _savePreferences,
        label: const Text('Save Changes'),
        icon: const Icon(Icons.save),
      ),
    );
  }
}