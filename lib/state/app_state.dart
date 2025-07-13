import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/models/router.dart' as model;

class AppState extends ChangeNotifier {
  final SecureStorageService _secureStorageService = SecureStorageService();
  final ApiService _apiService = ApiService();

  String? _sysauth;
  String? _ipAddress;
  bool _useHttps = false;
  bool _isLoading = false;
  String? _errorMessage;

  Map<String, dynamic>? _dashboardData;
  bool _isDashboardLoading = false;
  String? _dashboardError;

  Timer? _throughputTimer;
  List<double> _rxHistory = [];
  List<double> _txHistory = [];
  double _currentRxRate = 0;
  double _currentTxRate = 0;
  Map<String, dynamic>? _lastStats;
  DateTime? _lastTimestamp;

  // Theme mode state
  ThemeMode _themeMode = ThemeMode.dark;
  static const String _themeModeKey = 'themeMode';

  List<model.Router> _routers = [];
  model.Router? _selectedRouter;

  List<model.Router> get routers => _routers;
  model.Router? get selectedRouter => _selectedRouter;

  AppState() {
    _loadThemeMode();
    loadRouters(); // Load routers on app start
  }

  Future<void> _loadThemeMode() async {
    final stored = await _secureStorageService.readValue(_themeModeKey);
    if (stored == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (stored == 'light') {
      _themeMode = ThemeMode.light;
    } else if (stored == 'system') {
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  ThemeMode get themeMode => _themeMode;
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _secureStorageService.writeValue(_themeModeKey, mode.name);
    notifyListeners();
  }

  String? get sysauth => _sysauth;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Map<String, dynamic>? get dashboardData => _dashboardData;
  List<double> get rxHistory => _rxHistory;
  List<double> get txHistory => _txHistory;
  double get currentRxRate => _currentRxRate;
  double get currentTxRate => _currentTxRate;
  bool get isDashboardLoading => _isDashboardLoading;
  String? get dashboardError => _dashboardError;

  Future<void> loadRouters() async {
    _routers = await _secureStorageService.getRouters();
    if (_routers.isNotEmpty && _selectedRouter == null) {
      _selectedRouter = _routers.first;
    }
    notifyListeners();
  }

  Future<void> addRouter(model.Router router) async {
    _routers.add(router);
    await _secureStorageService.saveRouters(_routers);
    _selectedRouter ??= router;
    notifyListeners();
  }

  Future<void> removeRouter(String id) async {
    final wasActive = _selectedRouter?.id == id;
    _routers.removeWhere((r) => r.id == id);
    await _secureStorageService.saveRouters(_routers);
    if (wasActive) {
      if (_routers.isNotEmpty) {
        await selectRouter(_routers.first.id);
      } else {
        _selectedRouter = null;
        _dashboardData = null;
        notifyListeners();
      }
    } else {
      notifyListeners();
    }
  }

  Future<void> selectRouter(String id) async {
    if (_routers.isEmpty) return;
    final found = _routers.firstWhere((r) => r.id == id, orElse: () => _routers.first);
    _isLoading = true;
    _dashboardError = null;
    
    // Clear throughput data when switching routers to prevent mixing data from different routers
    _cancelThroughputTimer();
    
    notifyListeners();
    final loginSuccess = await login(found.ipAddress, found.username, found.password, found.useHttps, fromRouter: true);
    if (loginSuccess) {
      _selectedRouter = found;
      await fetchDashboardData();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateRouter(model.Router router) async {
    final idx = _routers.indexWhere((r) => r.id == router.id);
    if (idx != -1) {
      _routers[idx] = router;
      if (_selectedRouter?.id == router.id) {
        _selectedRouter = router;
      }
      await _secureStorageService.saveRouters(_routers);
      notifyListeners();
    }
  }

  Future<bool> login(String ip, String user, String pass, bool useHttps, {bool fromRouter = false}) async {
    _isLoading = true;
    _errorMessage = null;
    
    // Clear throughput data when logging in to prevent mixing data from different sessions
    _cancelThroughputTimer();
    
    notifyListeners();

    try {
      final token = await _apiService.login(ip, user, pass, useHttps);
      if (token != null) {
        _sysauth = token;
        _ipAddress = ip;
        _useHttps = useHttps;
        if (!fromRouter) {
          // If not from router selection, add or update router
          final id = '$ip-$user';
          final router = model.Router(
            id: id,
            ipAddress: ip,
            username: user,
            password: pass,
            useHttps: useHttps,
          );
          final idx = _routers.indexWhere((r) => r.id == id);
          if (idx == -1) {
            await addRouter(router);
          } else {
            await updateRouter(router);
          }
          _selectedRouter = router;
        }
        await _secureStorageService.saveCredentials(
          ipAddress: ip,
          username: user,
          password: pass,
          useHttps: useHttps,
        );
        await fetchDashboardData();
        _startThroughputTimer();
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Login Failed: Invalid credentials or host unreachable.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'An error occurred: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void logout() {
    _sysauth = null;
    _ipAddress = null;
    _useHttps = false;
    _dashboardData = null;
    _dashboardError = null;
    _cancelThroughputTimer();
    _secureStorageService.clearCredentials();
    // Optionally, do not clear routers or selectedRouter
    notifyListeners();
  }

  Future<void> fetchDashboardData() async {
    if (_isDashboardLoading || _selectedRouter == null || _sysauth == null) return;
    final ip = _selectedRouter!.ipAddress;
    final useHttps = _selectedRouter!.useHttps;

    _isDashboardLoading = true;
    _dashboardError = null;
    notifyListeners();

    try {
      // Perform all API calls in parallel
      final results = await Future.wait([
        _apiService.call(ip, _sysauth!, useHttps, object: 'system', method: 'board', params: {}),
        _apiService.call(ip, _sysauth!, useHttps, object: 'system', method: 'info', params: {}),
        _apiService.call(ip, _sysauth!, useHttps, object: 'luci-rpc', method: 'getNetworkDevices', params: {}),
        _apiService.call(ip, _sysauth!, useHttps, object: 'network.interface', method: 'dump', params: {}),
        _apiService.call(ip, _sysauth!, useHttps, object: 'luci-rpc', method: 'getWirelessDevices', params: {}),
        _apiService.call(ip, _sysauth!, useHttps, object: 'luci-rpc', method: 'getDHCPLeases', params: {}),
        _apiService.call(ip, _sysauth!, useHttps, object: 'uci', method: 'get', params: {'config': 'wireless'}),
      ]);

      // Helper to safely extract data and handle errors from LuCI's [status, data] responses
      dynamic getData(dynamic result) {
        if (result is List && result.length > 1) {
          if (result[0] == 0) {
            return result[1]; // Success
          } else {
            // Throw an exception with the error message from the API
            final errorMessage = result[1] is String ? result[1] : 'Unknown API Error';
            throw Exception(errorMessage);
          }
        }
        // Handle cases where the result is not in the expected format
        return result;
      }

      final networkData = getData(results[2]) as Map<String, dynamic>?;
      final interfaceDump = getData(results[3]) as Map<String, dynamic>?;
      final wirelessData = getData(results[4]) as Map<String, dynamic>?;
      final dhcpLeases = getData(results[5]) as Map<String, dynamic>?;
      final uciWirelessConfig = getData(results[6]);

      // Fetch WireGuard peer information for WireGuard interfaces
      final wireguardData = <String, dynamic>{};
      if (interfaceDump != null && interfaceDump['interface'] is List) {
        // Check if there are any WireGuard interfaces
        final hasWireGuardInterfaces = interfaceDump['interface'].any((interface) {
          if (interface is Map<String, dynamic>) {
            final proto = interface['proto'] as String?;
            return proto == 'wireguard';
          }
          return false;
        });

        if (hasWireGuardInterfaces) {
          // Fetch all WireGuard data at once
          final allWireGuardData = await _apiService.fetchWireGuardPeers(
            ipAddress: ip,
            sysauth: _sysauth!,
            useHttps: useHttps,
            interface: '', // Empty string to get all interfaces
          );
          
          if (allWireGuardData != null) {
            // The new endpoint returns data for all interfaces
            // We need to extract data for each WireGuard interface
            for (final interface in interfaceDump['interface']) {
              if (interface is Map<String, dynamic>) {
                final ifname = interface['interface'] as String?;
                final proto = interface['proto'] as String?;
                if (proto == 'wireguard' && ifname != null) {
                  // Look for this interface in the WireGuard data
                  final interfaceData = allWireGuardData[ifname];
                  
                  if (interfaceData != null) {
                    wireguardData[ifname] = interfaceData;
                  }
                }
              }
            }
          }
        }
      }

      // Throughput calculation
      final wanDeviceNames = <String>{};
      if (interfaceDump != null && interfaceDump['interface'] is List) {
        for (final interface in interfaceDump['interface']) {
          if (interface is Map<String, dynamic>) {
            final ifname = interface['interface'] as String?;
            final proto = interface['proto'] as String?;
            // Identify WAN interfaces by name convention or protocol
            if (ifname != null && (ifname.startsWith('wan') || proto == 'pppoe')) {
              final device = interface['device'] as String?;
              if (device != null) {
                wanDeviceNames.add(device);
              }
            }
          }
        }
      }

      final now = DateTime.now();
      if (_lastStats != null && _lastTimestamp != null) {
        final elapsedSeconds = now.difference(_lastTimestamp!).inMilliseconds / 1000.0;

        // Only calculate throughput if we have a reasonable time difference (at least 0.1 seconds)
        // This prevents artificially high rates from very small time differences while being more responsive
        if (elapsedSeconds >= 0.1) {
          final lastRx = _calculateTotalBytes(_lastStats, 'rx_bytes', wanDeviceNames: wanDeviceNames);
          final lastTx = _calculateTotalBytes(_lastStats, 'tx_bytes', wanDeviceNames: wanDeviceNames);
          final currentRx = _calculateTotalBytes(networkData, 'rx_bytes', wanDeviceNames: wanDeviceNames);
          final currentTx = _calculateTotalBytes(networkData, 'tx_bytes', wanDeviceNames: wanDeviceNames);

          // Calculate rates with a reasonable maximum to prevent spikes
          final rxRate = max(0, (currentRx - lastRx) / elapsedSeconds);
          final txRate = max(0, (currentTx - lastTx) / elapsedSeconds);
          
          // Cap the rates to prevent unrealistic spikes (e.g., 1 GB/s)
          const maxRate = 1000.0 * 1024.0 * 1024.0; // 1 GB/s - more realistic for modern connections
          _currentRxRate = min(rxRate.toDouble(), maxRate);
          _currentTxRate = min(txRate.toDouble(), maxRate);

          _rxHistory.add(_currentRxRate);
          _txHistory.add(_currentTxRate);
          if (_rxHistory.length > 50) _rxHistory.removeAt(0);
          if (_txHistory.length > 50) _txHistory.removeAt(0);
        }
        // If elapsedSeconds is too small, we skip the calculation but still update the timestamp
        // to prevent accumulation of small time differences
      }

      _lastStats = networkData;
      _lastTimestamp = now;

      _dashboardData = {
        'boardInfo': getData(results[0]),
        'sysInfo': getData(results[1]),
        'networkDevices': networkData,
        'interfaceDump': interfaceDump,
        'wireless': wirelessData,
        'dhcpLeases': dhcpLeases,
        'wan': _extractWanData(interfaceDump),
        'uciWirelessConfig': uciWirelessConfig,
        'wireguard': wireguardData,
      };

      // Hybrid approach: update lastKnownHostname for the selected router
      final boardInfo = _dashboardData?['boardInfo'] as Map<String, dynamic>?;
      final hostname = boardInfo?['hostname']?.toString();
      if (_selectedRouter != null && hostname != null && hostname.isNotEmpty) {
        final idx = _routers.indexWhere((r) => r.id == _selectedRouter!.id);
        if (idx != -1) {
          _routers[idx] = _routers[idx].copyWith(lastKnownHostname: hostname);
          await _secureStorageService.saveRouters(_routers);
        }
      }
    } catch (e) {
      final errorMessage = e.toString();
      if (errorMessage.contains('Access denied')) {
        _dashboardError = 'Access Denied: Check RPC permissions for this user.';
      } else {
        _dashboardError = 'Failed to fetch dashboard data: $e';
      }
      // Clear dashboard data when there's an error so we don't show stale data
      _dashboardData = null;
    } finally {
      _isDashboardLoading = false;
      notifyListeners();
    }
  }

  Map<String, dynamic>? _extractWanData(Map<String, dynamic>? interfaceDump) {
    if (interfaceDump == null || interfaceDump['interface'] == null) return null;
    try {
      for (var interface in interfaceDump['interface']) {
        if (interface['route'] is List) {
          for (var route in interface['route']) {
            if (route is Map &&
                route['target'] == '0.0.0.0' &&
                route['mask'] == 0) {
              return interface;
            }
          }
        }
      }
    } catch (e) {
  
      return null;
    }
    return null;
  }

    num _calculateTotalBytes(Map<String, dynamic>? networkData, String key, {Set<String>? wanDeviceNames}) {
    if (networkData == null) return 0;
    num total = 0;
    networkData.forEach((devName, devData) {
      // If wanDeviceNames is null, count all devices (old behavior).
      // Otherwise, only count devices in the set.
      if (wanDeviceNames == null || wanDeviceNames.contains(devName)) {
        if (devData is Map<String, dynamic> &&
            devData['stats'] is Map<String, dynamic> &&
            devData['stats'][key] != null) {
          total += devData['stats'][key];
        }
      }
    });
    return total;
  }

  void _startThroughputTimer() {
    _throughputTimer?.cancel();
    _throughputTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      fetchDashboardData();
    });
  }

  void _cancelThroughputTimer() {
    _throughputTimer?.cancel();
    _rxHistory = [];
    _txHistory = [];
    _currentRxRate = 0;
    _currentTxRate = 0;
    _lastStats = null;
    _lastTimestamp = null;
  }

  Future<bool> reboot() async {
    if (_sysauth == null || _ipAddress == null) return false;

    try {
      return await _apiService.reboot(_ipAddress!, _sysauth!, _useHttps);
    } catch (e) {
      return false;
    }
  }

  Future<bool> setWirelessRadioState(String device, bool enabled) async {
    if (_sysauth == null || _ipAddress == null) return false;

    try {
      // 1. Set the disabled state
      await _apiService.call(
        _ipAddress!,
        _sysauth!,
        _useHttps,
        object: 'uci',
        method: 'set',
        params: {
          'config': 'wireless',
          'section': device,
          'values': {'disabled': enabled ? '0' : '1'}
        },
      );

      // 2. Commit the changes
      await _apiService.call(
        _ipAddress!,
        _sysauth!,
        _useHttps,
        object: 'uci',
        method: 'commit',
        params: {'config': 'wireless'},
      );

      // 3. Reload wifi to apply changes
      await _apiService.call(
        _ipAddress!,
        _sysauth!,
        _useHttps,
        object: 'system',
        method: 'exec',
        params: {'command': 'wifi reload'},
      );

      // Refresh dashboard data to reflect the change
      await fetchDashboardData();

      return true;
    } catch (e) {
      _dashboardError = 'Failed to toggle Wi-Fi: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> tryAutoLogin() async {
    final credentials = await _secureStorageService.getCredentials();
    final ip = credentials['ipAddress'];
    final user = credentials['username'];
    final pass = credentials['password'];
    final useHttps = credentials['useHttps'] == 'true';

    if (ip != null && user != null && pass != null) {
      // Automatically try to log in with stored credentials
      return await login(ip, user, pass, useHttps);
    }

    // No stored credentials, so no auto-login
    return false;
  }

  /// Fetch all associated wireless MAC addresses from all wireless interfaces
  Future<Set<String>> fetchAllAssociatedWirelessMacs() async {
    final Set<String> macs = {};
    if (_ipAddress == null || _sysauth == null) return macs;
    // Extract wireless interface names from dashboardData['wireless']
    final wirelessData = _dashboardData?['wireless'] as Map<String, dynamic>?;
    if (wirelessData != null) {
      for (final radio in wirelessData.values) {
        final interfaces = radio['interfaces'] as List<dynamic>?;
        if (interfaces != null) {
          for (final iface in interfaces) {
            final config = iface['config'] ?? {};
            final iwinfo = iface['iwinfo'] ?? {};
            final ifname = iface['ifname'] ?? iwinfo['ifname'] ?? config['ifname'] ?? config['device'];
            if (ifname != null) {
              final macList = await _apiService.fetchAssociatedStations(
                ipAddress: _ipAddress!,
                sysauth: _sysauth!,
                useHttps: _useHttps,
                interface: ifname.toString(),
              );
              macs.addAll(macList.map((m) => m.toLowerCase()));
            }
          }
        }
      }
    }
    return macs;
  }
}
