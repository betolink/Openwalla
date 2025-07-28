import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// HTTP client manager that provides secure client instances with proper
/// certificate validation and connection pooling
class HttpClientManager {
  static final HttpClientManager _instance = HttpClientManager._internal();
  factory HttpClientManager() => _instance;
  HttpClientManager._internal();

  final Map<String, http.Client> _clients = {};
  final Map<String, bool> _userAcceptedCerts = {};

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
      
      // In debug mode, allow self-signed certificates for development
      if (kDebugMode) {
        print('Warning: Accepting self-signed certificate for $certHost:$port');
        print('Certificate subject: ${cert.subject}');
        print('Certificate issuer: ${cert.issuer}');
        return true;
      }
      
      // Check if user has already accepted this certificate
      if (_userAcceptedCerts[certKey] == true) {
        return true;
      }
      
      // In production, show warning dialog for untrusted certificates
      if (context != null && context.mounted) {
        _showCertificateWarning(context, cert, certHost, port, certKey);
      }
      
      return _userAcceptedCerts[certKey] == true;
    };

    return IOClient(httpClient);
  }

  /// Shows a warning dialog for untrusted certificates
  Future<void> _showCertificateWarning(
    BuildContext context,
    X509Certificate cert,
    String host,
    int port,
    String certKey,
  ) async {
    if (!context.mounted) return;
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => CertificateWarningDialog(
        certificate: cert,
        host: host,
        port: port,
      ),
    );
    
    if (result == true) {
      _userAcceptedCerts[certKey] = true;
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
    _userAcceptedCerts.clear();
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