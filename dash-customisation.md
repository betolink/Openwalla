## Dashboard Customization Feature Implementation Plan

### 1. Create Dashboard Preferences Model (lib/models/dashboard_preferences.dart)

class DashboardPreferences {
  final Set<String> enabledWirelessInterfaces;
  final Set<String> enabledWiredInterfaces;
  final String? primaryThroughputInterface;
  final bool showAllThroughput;

  DashboardPreferences({
    this.enabledWirelessInterfaces = const {},
    this.enabledWiredInterfaces = const {},
    this.primaryThroughputInterface,
    this.showAllThroughput = true,
  });

  Map<String, dynamic> toJson() => {
    'enabledWirelessInterfaces': enabledWirelessInterfaces.toList(),
    'enabledWiredInterfaces': enabledWiredInterfaces.toList(),
    'primaryThroughputInterface': primaryThroughputInterface,
    'showAllThroughput': showAllThroughput,
  };

  factory DashboardPreferences.fromJson(Map<String, dynamic> json) {
    return DashboardPreferences(
      enabledWirelessInterfaces: Set<String>.from(json['enabledWirelessInterfaces'] ?? []),
      enabledWiredInterfaces: Set<String>.from(json['enabledWiredInterfaces'] ?? []),
      primaryThroughputInterface: json['primaryThroughputInterface'],
      showAllThroughput: json['showAllThroughput'] ?? true,
    );
  }
}

### 2. Update AppState (lib/state/app_state.dart)

Add dashboard preferences management:

// Add to class properties
DashboardPreferences _dashboardPreferences = DashboardPreferences();
DashboardPreferences get dashboardPreferences => _dashboardPreferences;

// Add methods
Future<void> loadDashboardPreferences() async {
  final json = await _secureStorageService.readValue('dashboard_preferences');
  if (json != null) {
    _dashboardPreferences = DashboardPreferences.fromJson(jsonDecode(json));
    notifyListeners();
  }
}

Future<void> saveDashboardPreferences(DashboardPreferences prefs) async {
  _dashboardPreferences = prefs;
  await _secureStorageService.writeValue(
    'dashboard_preferences',
    jsonEncode(prefs.toJson())
  );
  notifyListeners();
}

### 3. Create Dashboard Customization Settings Screen (lib/screens/dashboard_customization_screen.dart)

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

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final appState = ref.read(appStateProvider);
    await appState.fetchDashboardData();
    _preferences = appState.dashboardPreferences;
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final dashboardData = appState.dashboardData;

    if (_isLoading) {
      return const Scaffold(
        appBar: LuciAppBar(title: 'Dashboard Customization', showBack: true),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: LuciAppBar(
        title: 'Dashboard Customization',
        showBack: true,
        actions: [
          TextButton(
            onPressed: _savePreferences,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        children: [
          _buildThroughputSection(dashboardData),
          _buildWirelessInterfacesSection(dashboardData),
          _buildWiredInterfacesSection(dashboardData),
        ],
      ),
    );
  }

  Widget _buildThroughputSection(Map<String, dynamic>? dashboardData) {
    final interfaces = _getAllInterfaces(dashboardData);

    return ExpansionTile(
      title: const Text('Throughput Graph'),
      subtitle: const Text('Select which interface to monitor'),
      initiallyExpanded: true,
      children: [
        RadioListTile<bool>(
          title: const Text('Show All Interfaces Combined'),
          value: true,
          groupValue: _preferences.showAllThroughput,
          onChanged: (value) {
            setState(() {
              _preferences = DashboardPreferences(
                enabledWirelessInterfaces: _preferences.enabledWirelessInterfaces,
                enabledWiredInterfaces: _preferences.enabledWiredInterfaces,
                showAllThroughput: true,
                primaryThroughputInterface: null,
              );
            });
          },
        ),
        RadioListTile<bool>(
          title: const Text('Show Specific Interface'),
          value: false,
          groupValue: _preferences.showAllThroughput,
          onChanged: (value) {
            setState(() {
              _preferences = DashboardPreferences(
                enabledWirelessInterfaces: _preferences.enabledWirelessInterfaces,
                enabledWiredInterfaces: _preferences.enabledWiredInterfaces,
                showAllThroughput: false,
                primaryThroughputInterface: interfaces.isNotEmpty ? interfaces.first : null,
              );
            });
          },
        ),
        if (!_preferences.showAllThroughput)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: DropdownButtonFormField<String>(
              value: _preferences.primaryThroughputInterface,
              decoration: const InputDecoration(
                labelText: 'Select Interface',
                border: OutlineInputBorder(),
              ),
              items: interfaces.map((iface) {
                return DropdownMenuItem(
                  value: iface,
                  child: Text(iface),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _preferences = DashboardPreferences(
                    enabledWirelessInterfaces: _preferences.enabledWirelessInterfaces,
                    enabledWiredInterfaces: _preferences.enabledWiredInterfaces,
                    showAllThroughput: false,
                    primaryThroughputInterface: value,
                  );
                });
              },
            ),
          ),
      ],
    );
  }

  Future<void> _savePreferences() async {
    final appState = ref.read(appStateProvider);
    await appState.saveDashboardPreferences(_preferences);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dashboard preferences saved')),
      );
      Navigator.of(context).pop();
    }
  }
}

### 4. Update Settings Screen (lib/screens/settings_screen.dart)

Add navigation to dashboard customization:

// Add after theme settings
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

### 5. Update Dashboard Screen (lib/screens/dashboard_screen.dart)

Modify to respect preferences:

// In _buildWirelessNetworksCard method
Widget _buildWirelessNetworksCard(AppState appState) {
  final prefs = appState.dashboardPreferences;
  final wirelessRadios = appState.dashboardData?['wireless'] as Map<String, dynamic>?;

  // Filter interfaces based on preferences
  List<Widget> networkCardWidgets = [];
  wirelessRadios?.forEach((radioName, radioData) {
    final interfaces = radioData['interfaces'] as List<dynamic>?;
    interfaces?.forEach((interface) {
      final ssid = interface['iwinfo']?['ssid'] ?? interface['config']?['ssid'];

      // Check if this interface is enabled in preferences
      if (prefs.enabledWirelessInterfaces.isEmpty ||
          prefs.enabledWirelessInterfaces.contains(ssid)) {
        // Add the card widget
      }
    });
  });

  // Similar filtering for wired interfaces
}

// Update throughput calculation
Widget _buildRealtimeThroughputCard(AppState appState) {
  final prefs = appState.dashboardPreferences;

  // If specific interface is selected, show only that interface's throughput
  if (!prefs.showAllThroughput && prefs.primaryThroughputInterface != null) {
    // Update throughput service to track specific interface
    appState.updateThroughputForInterface(prefs.primaryThroughputInterface!);
  }

  // Rest of the implementation
}

### 6. Update Throughput Service (lib/services/throughput_service.dart)

Add per-interface tracking:

class ThroughputService {
  // Add per-interface tracking
  final Map<String, Queue<double>> _rxHistoryPerInterface = {};
  final Map<String, Queue<double>> _txHistoryPerInterface = {};
  final Map<String, double> _currentRxRatePerInterface = {};
  final Map<String, double> _currentTxRatePerInterface = {};

  // Add method to get specific interface throughput
  List<double> getRxHistoryForInterface(String interface) {
    return _rxHistoryPerInterface[interface]?.toList() ?? [];
  }

  List<double> getTxHistoryForInterface(String interface) {
    return _txHistoryPerInterface[interface]?.toList() ?? [];
  }

  double getCurrentRxRateForInterface(String interface) {
    return _currentRxRatePerInterface[interface] ?? 0.0;
  }

  double getCurrentTxRateForInterface(String interface) {
    return _currentTxRatePerInterface[interface] ?? 0.0;
  }

  // Update the updateThroughput method to track per-interface
  void updateThroughput(
    Map<String, dynamic>? networkData,
    Set<String> wanDeviceNames, {
    String? specificInterface,
  }) {
    // If specific interface requested, calculate only for that
    if (specificInterface != null) {
      _updateInterfaceThroughput(networkData, specificInterface);
    } else {
      // Update overall throughput as before
      // Also update per-interface for all interfaces
      networkData?.forEach((devName, devData) {
        _updateInterfaceThroughput({devName: devData}, devName);
      });
    }
  }
}

### 7. Update Main App to load preferences on startup

In lib/main.dart or AppState._initialize():

Future<void> _initialize() async {
  await _loadReviewerMode();
  _initializeServices();
  await _loadThemeMode();
  await loadDashboardPreferences(); // Add this line
  await loadRouters();
}

This implementation provides:

• A dedicated settings screen for dashboard customization
• Selection of which interfaces to show throughput graphs for
• Choice between combined throughput or specific interface throughput
• Selection of which wireless and wired interfaces appear on dashboard
• Persistence of preferences across app restarts
• Responsive UI that updates based on user selections

The feature integrates seamlessly with the existing codebase while following the established patterns and conventions.