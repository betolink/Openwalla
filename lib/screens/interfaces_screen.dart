import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:flutter/services.dart';
import 'package:luci_mobile/models/interface.dart';
import 'dart:math';
import 'package:luci_mobile/widgets/luci_app_bar.dart';


class InterfacesScreen extends StatelessWidget {
  const InterfacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);

    return Scaffold(
      appBar: const LuciAppBar(title: 'Interfaces'),
      body: RefreshIndicator(
        onRefresh: () => appState.fetchDashboardData(),
        child: Selector<AppState, (bool, String?, Map<String, dynamic>?)>(
          selector: (_, state) => (
            state.isDashboardLoading,
            state.dashboardError,
            state.dashboardData,
          ),
          builder: (context, data, _) {
            final (isLoading, dashboardError, dashboardData) = data;

            if (isLoading && dashboardData == null) {
              return const LuciLoadingWidget();
            }

            if (dashboardError != null && dashboardData == null) {
              return LuciErrorDisplay(
                title: 'Failed to Load Interfaces',
                message: 'Could not connect to the router. Please check your network connection and router settings.',
                actionLabel: 'Retry',
                onAction: () => appState.fetchDashboardData(),
                icon: Icons.wifi_off_rounded,
              );
            }

            if (dashboardData == null) {
              return LuciEmptyState(
                title: 'No Interface Data',
                message: 'Unable to fetch interface information. Pull down to refresh or tap the button below.',
                icon: Icons.device_hub_outlined,
                actionLabel: 'Fetch Data',
                onAction: () => appState.fetchDashboardData(),
              );
            }

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: LuciSectionHeader('Wired')),
                _buildWiredInterfacesList(),
                SliverToBoxAdapter(child: LuciSectionHeader('Wireless')),
                _buildWirelessInterfacesList(),
                SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(bottom: 16), child: SizedBox.shrink())),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildWiredInterfacesList() {
    return Selector<AppState, List<NetworkInterface>>(
      selector: (_, state) {
        final dynamic detailedData = state.dashboardData?['interfaceDump'];
        final dynamic statsDataSource = state.dashboardData?['networkDevices'];
        var interfacesList = <NetworkInterface>[];

        if (detailedData is Map &&
            detailedData.containsKey('interface') &&
            detailedData['interface'] is List &&
            statsDataSource is Map) {
          final List<dynamic> interfaceDataList = detailedData['interface'];
          final Map<String, dynamic> networkStatsMap = Map<String, dynamic>.from(statsDataSource);

          interfacesList = interfaceDataList.whereType<Map<String, dynamic>>().map((detailedInterfaceMap) {
            final stats = detailedInterfaceMap['stats'];
            if (stats == null || (stats is Map && stats.isEmpty)) {
              final String? deviceName = detailedInterfaceMap['l3_device'] ?? detailedInterfaceMap['device'];
              if (deviceName != null) {
                final statsContainer = networkStatsMap[deviceName];
                if (statsContainer is Map && statsContainer['stats'] is Map) {
                  detailedInterfaceMap['stats'] = statsContainer['stats'];
                }
              }
            }
            return NetworkInterface.fromJson(detailedInterfaceMap);
          }).toList();
        }
        return interfacesList;
      },
      builder: (context, interfaces, _) {
        if (interfaces.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final iface = interfaces[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                child: _UnifiedNetworkCard(
                  name: iface.name.toUpperCase(),
                  subtitle: _buildMinimalInterfaceSubtitle(iface),
                  isUp: iface.isUp,
                  icon: _getInterfaceIcon(iface.protocol),
                  details: _buildWiredDetails(context, iface),
                ),
              );
            },
            childCount: interfaces.length,
          ),
        );
      },
    );
  }

  Widget _buildWirelessInterfacesList() {
    return Selector<AppState, List<Map<String, dynamic>>>(
      selector: (_, state) {
        final dashboardData = state.dashboardData;
        final wirelessData = dashboardData?['wireless'] as Map<String, dynamic>?;
        final uciWirelessConfig = dashboardData?['uciWirelessConfig'];
        final interfacesList = <Map<String, dynamic>>[];

        final uciRadios = <String, Map>{};
        final uciInterfaces = <String, Map>{};

        final uciValues = uciWirelessConfig?['values'] as Map?;
        if (uciValues != null) {
          uciValues.forEach((key, value) {
            final typedValue = value as Map?;
            if (typedValue?['.type'] == 'wifi-device') {
              uciRadios[key] = typedValue!;
            } else if (typedValue?['.type'] == 'wifi-iface') {
              uciInterfaces[key] = typedValue!;
            }
          });
        }

        final runtimeInterfaces = <String>{};
        if (wirelessData != null) {
          wirelessData.forEach((radioName, radioData) {
            final interfaces = radioData['interfaces'] as List<dynamic>?;
            if (interfaces != null) {
              for (final iface in interfaces) {
                final config = iface['config'] ?? {};
                final iwinfo = iface['iwinfo'] ?? {};
                final uciName = iface['section'] as String?;
                if (uciName != null) {
                  runtimeInterfaces.add(uciName);
                }

                final isRadioEnabled = uciRadios[radioName]?['disabled'] != '1';
                final isIfaceEnabled = config['disabled'] != '1';
                final isEnabled = isRadioEnabled && isIfaceEnabled;

                interfacesList.add({
                  'name': config['ssid'] ?? iwinfo['ssid'] ?? 'Unnamed',
                  'subtitle': '${config['mode']?.toUpperCase() ?? iwinfo['mode']?.toUpperCase() ?? 'N/A'} • Ch. ${iwinfo['channel']?.toString() ?? config['channel']?.toString() ?? 'N/A'}',
                  'isEnabled': isEnabled,
                  'details': {
                    'Device': config['device'] ?? radioName,
                    'Mode': config['mode'] ?? iwinfo['mode'] ?? 'N/A',
                    'Channel': iwinfo['channel']?.toString() ?? config['channel']?.toString() ?? 'N/A',
                    'Signal': '${iwinfo['signal']?.toString() ?? '--'} dBm',
                    'Network': (config['network'] is List) ? (config['network'] as List).join(', ') : config['network'] ?? 'N/A',
                  }
                });
              }
            }
          });
        }

        uciInterfaces.forEach((uciName, config) {
          if (!runtimeInterfaces.contains(uciName)) {
            final radioName = config['device'];
            final isRadioEnabled = uciRadios[radioName]?['disabled'] != '1';
            final isIfaceEnabled = config['disabled'] != '1';
            final isEnabled = isRadioEnabled && isIfaceEnabled;

            interfacesList.add({
              'name': config['ssid'] ?? 'Unnamed',
              'subtitle': '${config['mode']?.toUpperCase() ?? 'N/A'} • Disabled',
              'isEnabled': isEnabled,
              'details': {
                'Device': radioName,
                'Mode': config['mode'] ?? 'N/A',
                'SSID': config['ssid'] ?? 'N/A',
                'Network': (config['network'] is List) ? (config['network'] as List).join(', ') : config['network'] ?? 'N/A',
              }
            });
          }
        });
        
        return interfacesList;
      },
      builder: (context, interfaces, _) {
        if (interfaces.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final iface = interfaces[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: _UnifiedNetworkCard(
                  name: iface['name'],
                  subtitle: iface['subtitle'],
                  isUp: iface['isEnabled'],
                  icon: Icons.wifi,
                  details: _buildGenericDetails(context, iface['details']),
                ),
              );
            },
            childCount: interfaces.length,
          ),
        );
      },
    );
  }

  Widget _buildWiredDetails(BuildContext context, NetworkInterface interface) {
    return Column(
      children: [
        _buildDetailRow(context, 'Device', interface.device),
        _buildDetailRow(context, 'Uptime', interface.formattedUptime),
        if (interface.ipAddress != null)
          _buildDetailRow(
            context,
            'IP Address',
            interface.ipAddress!,
            onTap: () => _copyToClipboard(context, interface.ipAddress!, 'IP Address'),
          ),
        if (interface.ipv6Addresses != null && interface.ipv6Addresses!.isNotEmpty)
          ...interface.ipv6Addresses!.map((ipv6) => _buildDetailRow(
                context,
                'IPv6 Address',
                ipv6,
                onTap: () => _copyToClipboard(context, ipv6, 'IPv6 Address'),
              )),
        if (interface.gateway != null)
          _buildDetailRow(
            context,
            'Gateway',
            interface.gateway!,
            onTap: () => _copyToClipboard(context, interface.gateway!, 'Gateway IP'),
          ),
        if (interface.dnsServers.isNotEmpty)
          _buildDetailRow(
            context,
            'DNS',
            interface.dnsServers.join(', '),
            onTap: () => _copyToClipboard(context, interface.dnsServers.join(', '), 'DNS Servers'),
          ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: _buildStatsRow(context, interface.stats),
        ),
      ],
    );
  }

  Widget _buildGenericDetails(BuildContext context, Map<String, dynamic> details) {
    return Column(
      children: details.entries.map((entry) {
        return _buildDetailRow(context, entry.key, entry.value.toString());
      }).toList(),
    );
  }

  Widget _buildDetailRow(BuildContext context, String title, String value, {VoidCallback? onTap}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface)),
            Row(
              children: [
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                ),
                if (onTap != null)
                  GestureDetector(
                    onTap: onTap,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8.0),
                      child: Icon(Icons.copy_all_outlined, size: 16, semanticLabel: 'Copy'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard'), duration: const Duration(seconds: 2)),
    );
  }

  Widget _buildStatsRow(BuildContext context, Map<String, dynamic> stats) {
    String formatBytes(int bytes) {
      if (bytes <= 0) return '0 B';
      const suffixes = ["B", "KB", "MB", "GB", "TB"];
      var i = (log(bytes) / log(1024)).floor();
      return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatColumn(context, 'Received', formatBytes(stats['rx_bytes'] ?? 0), Icons.arrow_downward, Colors.green),
        _buildStatColumn(context, 'Transmitted', formatBytes(stats['tx_bytes'] ?? 0), Icons.arrow_upward, Colors.blue),
      ],
    );
  }

  Widget _buildStatColumn(BuildContext context, String label, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface)),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  IconData _getInterfaceIcon(String protocol) {
    switch (protocol.toLowerCase()) {
      case 'wireguard':
        return Icons.shield_outlined;
      case 'static':
        return Icons.settings_ethernet;
      case 'dhcp':
        return Icons.dns_outlined;
      default:
        return Icons.device_hub_outlined;
    }
  }

  String _buildMinimalInterfaceSubtitle(NetworkInterface iface) {
    final v4 = iface.ipAddress;
    final v6s = iface.ipv6Addresses ?? [];
    final v6 = v6s.isNotEmpty ? v6s.first : null;
    String? shown;
    int extra = 0;
    if (v4 != null) {
      shown = v4;
      if (v6 != null) extra++;
    } else if (v6 != null) {
      shown = v6;
    }
    if (shown == null) return iface.protocol;
    if (extra > 0) {
      return '${iface.protocol} • $shown  +$extra';
    } else {
      return '${iface.protocol} • $shown';
    }
  }
}

class LuciSectionHeader extends StatelessWidget {
  final String title;
  const LuciSectionHeader(this.title, {super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _UnifiedNetworkCard extends StatefulWidget {
  final String name;
  final String subtitle;
  final bool isUp;
  final IconData icon;
  final Widget details;

  const _UnifiedNetworkCard({
    required this.name,
    required this.subtitle,
    required this.isUp,
    required this.icon,
    required this.details,
  });

  @override
  State<_UnifiedNetworkCard> createState() => _UnifiedNetworkCardState();
}

class _UnifiedNetworkCardState extends State<_UnifiedNetworkCard> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final card = Card(
      elevation: _isExpanded ? 6 : 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
        side: BorderSide(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: _toggleExpand,
            borderRadius: BorderRadius.circular(18.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.13),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.icon,
                          color: widget.isUp ? colorScheme.primary : colorScheme.onSurface,
                          size: 22,
                          semanticLabel: 'Interface icon',
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Tooltip(
                          message: widget.isUp ? 'Interface is up' : 'Interface is down',
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: widget.isUp ? Colors.green : colorScheme.error,
                              shape: BoxShape.circle,
                              border: Border.all(color: colorScheme.surface, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          semanticsLabel: 'Interface name: ${widget.name}',
                        ),
                        const SizedBox(height: 4),
                        Container(
                          margin: const EdgeInsets.only(right: 32),
                          child: Divider(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.10),
                            thickness: 1,
                            height: 8,
                          ),
                        ),
                        Text(
                          widget.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.1,
                          ),
                          semanticsLabel: 'Interface details: ${widget.subtitle}',
                        ),
                      ],
                    ),
                  ),
                  if (!widget.isUp)
                    Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: Chip(
                        label: const Text('OFF'),
                        labelStyle: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onError),
                        backgroundColor: colorScheme.error.withValues(alpha: 0.7),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: colorScheme.onSurfaceVariant,
                    size: 26,
                    semanticLabel: _isExpanded ? 'Collapse details' : 'Expand details',
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Column(
              children: [
                const Divider(height: 1, indent: 18, endIndent: 18),
                widget.details,
              ],
            ),
        ],
      ),
    );

    if (!widget.isUp) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0,      0,      0,      1, 0,
        ]),
        child: card,
      );
    }
    return card;
  }
}
