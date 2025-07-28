abstract class IAuthService {
  Future<void> login(String ipAddress, String username, String password, bool useHttps);
  Future<bool> tryAutoLogin(String? ipAddress, String? username, String? password, bool? useHttps);
  Future<void> logout();
  Future<bool> checkRouterAvailability(String ipAddress, bool useHttps);
  
  String? get sysauth;
  String? get ipAddress;
  bool get useHttps;
  bool get isAuthenticated;
}