import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/services/interfaces/auth_service_interface.dart';

class RealAuthService implements IAuthService {
  final SecureStorageService _secureStorageService = SecureStorageService();
  final IApiService _apiService;

  String? _sysauth;
  String? _ipAddress;
  bool _useHttps = false;

  RealAuthService(this._apiService);

  @override
  String? get sysauth => _sysauth;
  @override
  String? get ipAddress => _ipAddress;
  @override
  bool get useHttps => _useHttps;
  @override
  bool get isAuthenticated => _sysauth != null;

  @override
  Future<void> login(String ipAddress, String username, String password, bool useHttps) async {
    await _login(ipAddress, username, password, useHttps);
  }

  Future<bool> _login(
    String ip,
    String user,
    String pass,
    bool useHttps,
  ) async {
    try {
      final token = await _apiService.login(ip, user, pass, useHttps);
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
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> tryAutoLogin(String? ipAddress, String? username, String? password, bool? useHttps) async {
    if (ipAddress != null && username != null && password != null && useHttps != null) {
      return await _login(ipAddress, username, password, useHttps);
    }
    return await _tryAutoLoginFromStorage();
  }

  Future<bool> _tryAutoLoginFromStorage() async {
    final credentials = await _secureStorageService.getCredentials();
    final ip = credentials['ipAddress'];
    final user = credentials['username'];
    final pass = credentials['password'];
    final useHttps = credentials['useHttps'] == 'true';

    if (ip != null && user != null && pass != null) {
      return await _login(ip, user, pass, useHttps);
    }

    return false;
  }

  @override
  Future<void> logout() async {
    _sysauth = null;  
    _ipAddress = null;
    _useHttps = false;
    await _secureStorageService.clearCredentials();
  }

  @override
  Future<bool> checkRouterAvailability(String ipAddress, bool useHttps) async {
    if (ipAddress.isEmpty) return false;
    
    try {
      final result = await _apiService.call(
        ipAddress,
        '',
        useHttps,
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