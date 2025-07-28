import 'package:flutter/material.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';

class AuthService {
  final SecureStorageService _secureStorageService = SecureStorageService();
  final ApiService _apiService = ApiService();

  String? _sysauth;
  String? _ipAddress;
  bool _useHttps = false;

  String? get sysauth => _sysauth;
  String? get ipAddress => _ipAddress;
  bool get useHttps => _useHttps;
  bool get isAuthenticated => _sysauth != null;

  Future<bool> login(
    String ip,
    String user,
    String pass,
    bool useHttps, {
    BuildContext? context,
  }) async {
    try {
      final token = await _apiService.login(ip, user, pass, useHttps, context: context);
      if (token != null) {
        _sysauth = token;
        _ipAddress = ip;
        _useHttps = useHttps;
        
        await _secureStorageService.saveCredentials(
          ipAddress: ip,
          username: user,
          password: pass,
          useHttps: useHttps,
        );
        
        return true;
      }
      return false;
    } catch (e) {
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
      return await login(ip, user, pass, useHttps);
    }

    return false;
  }

  void logout() {
    _sysauth = null;  
    _ipAddress = null;
    _useHttps = false;
    _secureStorageService.clearCredentials();
  }

  Future<bool> checkRouterAvailability() async {
    if (_ipAddress == null) return false;
    
    try {
      final result = await _apiService.call(
        _ipAddress!,
        '',
        _useHttps,
        object: 'system',
        method: 'board',
        params: {},
      );
      return result != null;
    } catch (e) {
      return false;
    }
  }
}