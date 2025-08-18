import 'dart:collection';
import 'dart:math';

class ThroughputService {
  final Queue<double> _rxHistory = Queue<double>();
  final Queue<double> _txHistory = Queue<double>();
  
  double _currentRxRate = 0;
  double _currentTxRate = 0;
  Map<String, dynamic>? _lastStats;
  DateTime? _lastTimestamp;
  
  // Smoothing variables
  double _previousRxRate = 0;
  double _previousTxRate = 0;
  
  // Per-interface tracking
  final Map<String, Queue<double>> _rxHistoryPerInterface = {};
  final Map<String, Queue<double>> _txHistoryPerInterface = {};
  final Map<String, double> _currentRxRatePerInterface = {};
  final Map<String, double> _currentTxRatePerInterface = {};
  final Map<String, Map<String, dynamic>?> _lastStatsPerInterface = {};
  final Map<String, DateTime?> _lastTimestampPerInterface = {};
  final Map<String, double> _previousRxRatePerInterface = {};
  final Map<String, double> _previousTxRatePerInterface = {};
  
  static const int _maxHistoryLength = 50;
  static const double _maxRate = 1000.0 * 1024.0 * 1024.0; // 1 GB/s
  static const double _minElapsedSeconds = 0.1;
  static const double _smoothingFactor = 0.7; // Lower = more smoothing

  List<double> get rxHistory => _rxHistory.toList();
  List<double> get txHistory => _txHistory.toList();
  double get currentRxRate => _currentRxRate;
  double get currentTxRate => _currentTxRate;
  
  // Interface-specific getters
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
  
  /// Applies exponential moving average smoothing to reduce data spikes
  double _smoothValue(double newValue, double previousValue) {
    if (previousValue == 0) return newValue;
    return previousValue + _smoothingFactor * (newValue - previousValue);
  }

  void updateThroughput(
    Map<String, dynamic>? networkData,
    Set<String> wanDeviceNames, {
    String? specificInterface,
  }) {
    final now = DateTime.now();
    
    // Update per-interface throughput
    if (networkData != null) {
      networkData.forEach((devName, devData) {
        _updateInterfaceThroughput(devName, devData, now);
      });
    }
    
    // Update overall throughput
    if (specificInterface != null) {
      // If specific interface requested, use only that interface's data
      if (networkData != null && networkData.containsKey(specificInterface)) {
        _updateSpecificInterfaceThroughput(
          specificInterface, 
          networkData[specificInterface], 
          now
        );
      }
    } else {
      // Update combined throughput as before
      if (_lastStats == null || _lastTimestamp == null) {
        _lastStats = networkData;
        _lastTimestamp = now;
        // Add an initial zero-rate data point so the UI has something to display
        _addToHistory(0.0, 0.0);
        return;
      }

      final elapsedSeconds = now.difference(_lastTimestamp!).inMilliseconds / 1000.0;

      // Only calculate throughput if we have a reasonable time difference
      if (elapsedSeconds >= _minElapsedSeconds) {
        final lastRx = _calculateTotalBytes(_lastStats, 'rx_bytes', wanDeviceNames: wanDeviceNames);
        final lastTx = _calculateTotalBytes(_lastStats, 'tx_bytes', wanDeviceNames: wanDeviceNames);
        final currentRx = _calculateTotalBytes(networkData, 'rx_bytes', wanDeviceNames: wanDeviceNames);
        final currentTx = _calculateTotalBytes(networkData, 'tx_bytes', wanDeviceNames: wanDeviceNames);

        // Calculate rates with a reasonable maximum to prevent spikes
        final rawRxRate = max(0, (currentRx - lastRx) / elapsedSeconds);
        final rawTxRate = max(0, (currentTx - lastTx) / elapsedSeconds);

        // Cap the rates to prevent unrealistic spikes
        final cappedRxRate = min(rawRxRate.toDouble(), _maxRate);
        final cappedTxRate = min(rawTxRate.toDouble(), _maxRate);
        
        // Apply smoothing to reduce abrupt changes
        _currentRxRate = _smoothValue(cappedRxRate, _previousRxRate);
        _currentTxRate = _smoothValue(cappedTxRate, _previousTxRate);
        
        // Update previous values for next smoothing calculation
        _previousRxRate = _currentRxRate;
        _previousTxRate = _currentTxRate;

        _addToHistory(_currentRxRate, _currentTxRate);
      }

      _lastStats = networkData;
      _lastTimestamp = now;
    }
  }
  
  void _updateInterfaceThroughput(String interface, dynamic devData, DateTime now) {
    if (devData == null || devData is! Map<String, dynamic>) return;
    
    final lastStats = _lastStatsPerInterface[interface];
    final lastTimestamp = _lastTimestampPerInterface[interface];
    
    if (lastStats == null || lastTimestamp == null) {
      _lastStatsPerInterface[interface] = devData;
      _lastTimestampPerInterface[interface] = now;
      
      // Initialize history for this interface
      _rxHistoryPerInterface.putIfAbsent(interface, () => Queue<double>());
      _txHistoryPerInterface.putIfAbsent(interface, () => Queue<double>());
      _rxHistoryPerInterface[interface]!.add(0.0);
      _txHistoryPerInterface[interface]!.add(0.0);
      return;
    }
    
    final elapsedSeconds = now.difference(lastTimestamp).inMilliseconds / 1000.0;
    
    if (elapsedSeconds >= _minElapsedSeconds) {
      final lastRx = (lastStats['stats']?['rx_bytes'] ?? 0) as num;
      final lastTx = (lastStats['stats']?['tx_bytes'] ?? 0) as num;
      final currentRx = (devData['stats']?['rx_bytes'] ?? 0) as num;
      final currentTx = (devData['stats']?['tx_bytes'] ?? 0) as num;
      
      final rawRxRate = max(0, (currentRx - lastRx) / elapsedSeconds);
      final rawTxRate = max(0, (currentTx - lastTx) / elapsedSeconds);
      
      final cappedRxRate = min(rawRxRate.toDouble(), _maxRate);
      final cappedTxRate = min(rawTxRate.toDouble(), _maxRate);
      
      // Apply smoothing to interface-specific rates
      final previousRx = _previousRxRatePerInterface[interface] ?? 0.0;
      final previousTx = _previousTxRatePerInterface[interface] ?? 0.0;
      
      _currentRxRatePerInterface[interface] = _smoothValue(cappedRxRate, previousRx);
      _currentTxRatePerInterface[interface] = _smoothValue(cappedTxRate, previousTx);
      
      // Update previous values for next smoothing calculation
      _previousRxRatePerInterface[interface] = _currentRxRatePerInterface[interface]!;
      _previousTxRatePerInterface[interface] = _currentTxRatePerInterface[interface]!;
      
      _addToInterfaceHistory(interface, _currentRxRatePerInterface[interface]!, _currentTxRatePerInterface[interface]!);
    }
    
    _lastStatsPerInterface[interface] = devData;
    _lastTimestampPerInterface[interface] = now;
  }
  
  void _updateSpecificInterfaceThroughput(String interface, dynamic devData, DateTime now) {
    if (devData == null || devData is! Map<String, dynamic>) return;
    
    final rxRate = _currentRxRatePerInterface[interface] ?? 0.0;
    final txRate = _currentTxRatePerInterface[interface] ?? 0.0;
    
    _currentRxRate = rxRate;
    _currentTxRate = txRate;
    
    // Use the interface's history for the main display
    final rxHist = _rxHistoryPerInterface[interface];
    final txHist = _txHistoryPerInterface[interface];
    
    if (rxHist != null && txHist != null) {
      _rxHistory.clear();
      _txHistory.clear();
      _rxHistory.addAll(rxHist);
      _txHistory.addAll(txHist);
    }
  }
  
  void _addToInterfaceHistory(String interface, double rxRate, double txRate) {
    final rxHist = _rxHistoryPerInterface.putIfAbsent(interface, () => Queue<double>());
    final txHist = _txHistoryPerInterface.putIfAbsent(interface, () => Queue<double>());
    
    rxHist.add(rxRate);
    txHist.add(txRate);
    
    // Maintain fixed queue size
    if (rxHist.length > _maxHistoryLength) {
      rxHist.removeFirst();
    }
    if (txHist.length > _maxHistoryLength) {
      txHist.removeFirst();
    }
  }

  void _addToHistory(double rxRate, double txRate) {
    _rxHistory.add(rxRate);
    _txHistory.add(txRate);
    
    // Maintain fixed queue size for O(1) performance
    if (_rxHistory.length > _maxHistoryLength) {
      _rxHistory.removeFirst();
    }
    if (_txHistory.length > _maxHistoryLength) {
      _txHistory.removeFirst();
    }
  }

  num _calculateTotalBytes(
    Map<String, dynamic>? networkData,
    String key, {
    Set<String>? wanDeviceNames,
  }) {
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

  void clear() {
    _rxHistory.clear();
    _txHistory.clear();
    _currentRxRate = 0;
    _currentTxRate = 0;
    _lastStats = null;
    _lastTimestamp = null;
    
    // Clear smoothing variables
    _previousRxRate = 0;
    _previousTxRate = 0;
    
    // Clear per-interface data
    _rxHistoryPerInterface.clear();
    _txHistoryPerInterface.clear();
    _currentRxRatePerInterface.clear();
    _currentTxRatePerInterface.clear();
    _lastStatsPerInterface.clear();
    _lastTimestampPerInterface.clear();
    _previousRxRatePerInterface.clear();
    _previousTxRatePerInterface.clear();
  }
}