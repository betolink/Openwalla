import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:luci_mobile/models/router.dart';

class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  static const String _routersKey = 'routers';

  Future<void> saveCredentials({
    required String ipAddress,
    required String username,
    required String password,
    required bool useHttps,
  }) async {
    await _storage.write(key: 'ipAddress', value: ipAddress);
    await _storage.write(key: 'username', value: username);
    await _storage.write(key: 'password', value: password);
    await _storage.write(key: 'useHttps', value: useHttps.toString());
  }

  Future<Map<String, String?>> getCredentials() async {
    final ipAddress = await _storage.read(key: 'ipAddress');
    final username = await _storage.read(key: 'username');
    final password = await _storage.read(key: 'password');
    final useHttps = await _storage.read(key: 'useHttps');
    return {
      'ipAddress': ipAddress,
      'username': username,
      'password': password,
      'useHttps': useHttps,
    };
  }

  Future<void> clearCredentials() async {
    await _storage.deleteAll();
  }

  Future<String?> readValue(String key) async {
    return await _storage.read(key: key);
  }

  Future<void> writeValue(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<void> saveRouters(List<Router> routers) async {
    final jsonList = routers.map((r) => r.toJson()).toList();
    await _storage.write(key: _routersKey, value: jsonEncode(jsonList));
  }

  Future<List<Router>> getRouters() async {
    final jsonString = await _storage.read(key: _routersKey);
    if (jsonString == null || jsonString.isEmpty) return [];
    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((e) => Router.fromJson(e)).toList();
  }

  Future<void> deleteRouter(String id) async {
    final routers = await getRouters();
    final updated = routers.where((r) => r.id != id).toList();
    await saveRouters(updated);
  }

  Future<void> updateRouter(Router router) async {
    final routers = await getRouters();
    final updated = [
      for (final r in routers)
        if (r.id == router.id) router else r
    ];
    await saveRouters(updated);
  }
}
