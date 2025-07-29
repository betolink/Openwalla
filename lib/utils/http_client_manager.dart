import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// HTTP client manager that provides secure client instances with proper
/// certificate validation and connection pooling
class HttpClientManager {
  static final HttpClientManager _instance = HttpClientManager._internal();
  factory HttpClientManager() => _instance;
  HttpClientManager._internal() {
    _loadAcceptedCertificates();
  }

  final Map<String, http.Client> _clients = {};
  final Map<String, bool> _userAcceptedCerts = {};
  static const String _acceptedCertsKey = 'accepted_certificates';

  /// Creates or returns a cached HTTP client for the given host
  /// In production builds, certificate validation is enforced with user warnings
  /// In debug builds, self-signed certificates can be allowed automatically
  http.Client getClient(String host, bool useHttps, {BuildContext? context}) {
    final key = '$host-$useHttps';
    
    if (_clients.containsKey(key)) {
      return _clients[key]!;
    }

    final client = _createSecureClient(host, useHttps, context: context);
    _clients[key] = client;
    return client;
  }

  http.Client _createSecureClient(String host, bool useHttps, {BuildContext? context}) {
    if (!useHttps) {
      return http.Client();
    }

    final httpClient = HttpClient();
    httpClient.connectionTimeout = const Duration(seconds: 10);
    
    // Certificate validation callback
    httpClient.badCertificateCallback = (cert, certHost, port) {
      final certKey = '$certHost:$port';
      
      // Check if user has already accepted this certificate
      if (_userAcceptedCerts[certKey] == true) {
        return true;
      }
      
      // Certificate not accepted yet - require user consent in both debug and release
      return false;
    };

    return IOClient(httpClient);
  }

  /// Load accepted certificates from secure storage
  Future<void> _loadAcceptedCertificates() async {
    try {
      final storage = const FlutterSecureStorage();
      final certsJson = await storage.read(key: _acceptedCertsKey);
      if (certsJson != null) {
        final certs = Map<String, dynamic>.from(jsonDecode(certsJson));
        _userAcceptedCerts.clear();
        certs.forEach((key, value) {
          if (value == true) {
            _userAcceptedCerts[key] = true;
          }
        });
      }
    } catch (e) {
      // Ignore errors loading certificates
    }
  }
  
  /// Save accepted certificates to secure storage
  Future<void> _saveAcceptedCertificates() async {
    try {
      final storage = const FlutterSecureStorage();
      await storage.write(key: _acceptedCertsKey, value: jsonEncode(_userAcceptedCerts));
    } catch (e) {
      // Ignore errors saving certificates
    }
  }

  /// Disposes of a specific client
  void disposeClient(String host, bool useHttps) {
    final key = '$host-$useHttps';
    final client = _clients.remove(key);
    client?.close();
  }

  /// Disposes of all cached clients
  void disposeAll() {
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
    // Don't clear accepted certificates on dispose
  }
  
  /// Clear accepted certificates (useful for logout or security reset)
  Future<void> clearAcceptedCertificates() async {
    // Clear in-memory certificates
    _userAcceptedCerts.clear();
    
    // Clear all cached HTTP clients
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
    
    // Delete from secure storage
    try {
      final storage = const FlutterSecureStorage();
      await storage.delete(key: _acceptedCertsKey);
    } catch (e) {
      // Ignore errors
    }
  }
  
  /// Clear certificates for a specific host
  Future<void> clearCertificatesForHost(String host) async {
    // Remove certificates for this host on port 443
    final certKey = '$host:443';
    _userAcceptedCerts.remove(certKey);
    
    // Close and remove cached HTTP clients for this host
    final keysToRemove = _clients.keys.where((key) => key.startsWith(host)).toList();
    for (final key in keysToRemove) {
      _clients[key]?.close();
      _clients.remove(key);
    }
    
    // Save the updated certificates
    await _saveAcceptedCertificates();
  }
  
  /// Prompts user to accept certificate for a given host
  /// Returns true if user accepts, false otherwise
  Future<bool> promptForCertificateAcceptance({
    required BuildContext context,
    required String host,
    required bool useHttps,
  }) async {
    if (!useHttps) return true; // Non-HTTPS doesn't need certificate acceptance
    if (!context.mounted) return false;
    
    // Check if already accepted
    final certKey = '$host:443';
    if (_userAcceptedCerts[certKey] == true) {
      return true;
    }
    
    // Try to make a test connection to trigger certificate validation
    final testClient = HttpClient();
    testClient.connectionTimeout = const Duration(seconds: 5);
    
    // Apply the same certificate validation logic
    testClient.badCertificateCallback = (cert, certHost, port) {
      return _userAcceptedCerts['$certHost:$port'] == true;
    };
    
    try {
      final uri = Uri.parse('https://$host');
      final request = await testClient.getUrl(uri);
      await request.close();
      // If we get here, certificate is already valid or accepted
      return true;
    } catch (e) {
      if (e is HandshakeException) {
        // Extract certificate details from the exception if possible
        // For now, show a simplified dialog
        if (context.mounted) {
          final result = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) => AlertDialog(
              icon: Icon(
                Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.error,
                size: 32,
              ),
              title: const Text('Certificate Warning'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The certificate for $host is not trusted by your device. This could indicate a security risk.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Only proceed if you trust this router and understand the security implications.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  child: const Text('Accept Risk'),
                ),
              ],
            ),
          );
          
          if (result == true) {
            // Store acceptance persistently
            _userAcceptedCerts['$host:443'] = true;
            await _saveAcceptedCertificates();
            return true;
          }
        }
      }
    } finally {
      testClient.close();
    }
    
    return false;
  }
}

/// Dialog for warning users about untrusted certificates
class CertificateWarningDialog extends StatelessWidget {
  final X509Certificate certificate;
  final String host;
  final int port;

  const CertificateWarningDialog({
    super.key,
    required this.certificate,
    required this.host,
    required this.port,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return AlertDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        color: colorScheme.error,
        size: 32,
      ),
      title: const Text('Certificate Warning'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The certificate for $host:$port is not trusted by your device. This could indicate a security risk.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Certificate Details:',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildCertDetail('Subject', certificate.subject),
                  _buildCertDetail('Issuer', certificate.issuer),
                  _buildCertDetail('Valid From', 
                    certificate.startValidity.toLocal().toString().split('.')[0]),
                  _buildCertDetail('Valid Until', 
                    certificate.endValidity.toLocal().toString().split('.')[0]),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Only proceed if you trust this router and understand the security implications.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          child: const Text('Accept Risk'),
        ),
      ],
    );
  }

  Widget _buildCertDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}