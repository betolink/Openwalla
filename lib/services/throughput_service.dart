import 'dart:collection';
import 'dart:math';

class ThroughputService {
  final Queue<double> _rxHistory = Queue<double>();
  final Queue<double> _txHistory = Queue<double>();
  
  double _currentRxRate = 0;
  double _currentTxRate = 0;
  Map<String, dynamic>? _lastStats;
  DateTime? _lastTimestamp;
  
  static const int _maxHistoryLength = 50;
  static const double _maxRate = 1000.0 * 1024.0 * 1024.0; // 1 GB/s
  static const double _minElapsedSeconds = 0.1;

  List<double> get rxHistory => _rxHistory.toList();
  List<double> get txHistory => _txHistory.toList();
  double get currentRxRate => _currentRxRate;
  double get currentTxRate => _currentTxRate;

  void updateThroughput(
    Map<String, dynamic>? networkData,
    Set<String> wanDeviceNames,
  ) {
    final now = DateTime.now();
    
    if (_lastStats == null || _lastTimestamp == null) {
      _lastStats = networkData;
      _lastTimestamp = now;
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
      final rxRate = max(0, (currentRx - lastRx) / elapsedSeconds);
      final txRate = max(0, (currentTx - lastTx) / elapsedSeconds);

      // Cap the rates to prevent unrealistic spikes
      _currentRxRate = min(rxRate.toDouble(), _maxRate);
      _currentTxRate = min(txRate.toDouble(), _maxRate);

      _addToHistory(_currentRxRate, _currentTxRate);
    }

    _lastStats = networkData;
    _lastTimestamp = now;
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
  }
}