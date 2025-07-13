import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

Uri _buildUrl(String ipAddress, bool useHttps, String path) {
  final scheme = useHttps ? 'https' : 'http';
  return Uri.parse('$scheme://$ipAddress$path');
}

class ApiService {
  http.Client createHttpClient(bool allowSelfSigned) {
    if (allowSelfSigned) {
      final ioc = HttpClient();
      ioc.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      return IOClient(ioc);
    }
    return http.Client();
  }

  Future<String?> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    if (useHttps) {
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
    }

    try {
      final uri = _buildUrl(ipAddress, useHttps, '/cgi-bin/luci/');
      final request = await client.postUrl(uri);
      request.followRedirects = false;

      final params =
          'luci_username=${Uri.encodeComponent(username)}&luci_password=${Uri.encodeComponent(password)}';
      final body = utf8.encode(params);

      request.headers.set('content-type', 'application/x-www-form-urlencoded');
      request.contentLength = body.length;
      request.add(body);

      final response = await request.close();

      if (response.statusCode == 302) {
        final sysauthCookie = response.cookies.firstWhere(
          (c) => c.name.contains('sysauth'),
          orElse: () => Cookie('invalid', 'invalid'),
        );
        if (sysauthCookie.name != 'invalid') {
          return sysauthCookie.value;
        }
      }
      return null;
    } catch (e) {
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
  }) async {
    final url = _buildUrl(ipAddress, useHttps, '/cgi-bin/luci/admin/ubus');
    final client = createHttpClient(useHttps);

    final rpcPayload = {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'call',
      'params': [
        sysauth,
        object,
        method,
        params ?? {},
      ]
    };

    try {
      final response = await client
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(rpcPayload),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['error'] != null) {
          throw Exception('RPC error: ${decoded['error']['message']}');
        }
        return decoded['result'];
      } else {
        throw Exception('Failed to call RPC: HTTP ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<bool> reboot(String ipAddress, String sysauth, bool useHttps) async {
    try {
      final result = await call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'system',
        method: 'reboot',
      );
      // A successful reboot call returns [0].
      if (result is List && result.isNotEmpty && result[0] == 0) {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Fetches associated stations (wireless clients) for a given wireless interface (e.g., wlan0)
  Future<List<String>> fetchAssociatedStations({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
  }) async {
    try {
      final result = await call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'iwinfo',
        method: 'assoclist',
        params: {'device': interface},
      );
      // The result is now a list with a 'results' key containing a list of station maps
      if (result is List && result.length > 1 && result[1] is Map && result[1]['results'] is List) {
        final resultsList = result[1]['results'] as List;
        return resultsList
            .map((entry) => (entry as Map<String, dynamic>)['mac']?.toString())
            .where((mac) => mac != null)
            .cast<String>()
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Fetches WireGuard peer information for a given interface
  /// If interface is empty, returns data for all WireGuard interfaces
  Future<Map<String, dynamic>?> fetchWireGuardPeers({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
  }) async {
    try {
      // Use the correct luci.wireguard.getWgInstances method
      final result = await call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'luci.wireguard',
        method: 'getWgInstances',
        params: {},
      );
      
      if (result is List && result.length > 1 && result[0] == 0) {
        final data = result[1] as Map<String, dynamic>?;
        if (data != null) {
          return _parseWireGuardFromInstances(data, interface);
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic>? _parseWireGuardFromInstances(Map<String, dynamic> data, String targetInterface) {
    final wireguardData = <String, dynamic>{};
    
    data.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        
        // Look for peers in the interface data
        final peers = <String, dynamic>{};
        
        // The structure might have peers in different formats
        if (value['peers'] is List) {
          final peersList = value['peers'] as List;
          for (final peer in peersList) {
            if (peer is Map<String, dynamic>) {
              final publicKey = peer['public_key'] as String?;
              if (publicKey != null) {
                peers[publicKey] = {
                  'public_key': publicKey,
                  'endpoint': peer['endpoint'] ?? 'N/A',
                  'last_handshake': int.tryParse(peer['latest_handshake']?.toString() ?? '0') ?? 0,
                };
              }
            }
          }
        } else if (value['peers'] is Map<String, dynamic>) {
          final peersMap = value['peers'] as Map<String, dynamic>;
          peersMap.forEach((peerKey, peerData) {
            if (peerData is Map<String, dynamic>) {
              peers[peerKey] = {
                'public_key': peerKey,
                'endpoint': peerData['endpoint'] ?? 'N/A',
                'last_handshake': int.tryParse(peerData['latest_handshake']?.toString() ?? '0') ?? 0,
              };
            }
          });
        }
        
        if (peers.isNotEmpty) {
          wireguardData[key] = {
            'interface': key,
            'peers': peers,
          };
        }
      }
    });
    
    if (targetInterface.isEmpty) {
      return wireguardData;
    } else {
      return wireguardData[targetInterface];
    }
  }
}
