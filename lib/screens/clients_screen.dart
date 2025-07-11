import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';


class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> with SingleTickerProviderStateMixin {
  String _searchQuery = '';
  int? _expandedClientIndex;
  late AnimationController _controller;
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _searchController = TextEditingController();
    _searchController.addListener(() {
      if (_searchQuery != _searchController.text) {
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FutureBuilder<Set<String>>(
      future: appState.fetchAllAssociatedWirelessMacs(),
      builder: (context, snapshot) {
        final wirelessMacs = snapshot.data ?? {};
        return Scaffold(
          appBar: const LuciAppBar(title: 'Clients'),
          body: RefreshIndicator(
            onRefresh: () => appState.fetchDashboardData(),
            child: Selector<AppState, (bool, String?, Map<String, dynamic>?)>(
              selector: (_, state) => (
                state.isDashboardLoading,
                state.dashboardError,
                state.dashboardData?['dhcpLeases'] as Map<String, dynamic>?
              ),
              builder: (context, data, _) {
                final (isLoading, dashboardError, dhcpData) = data;

                if (isLoading && dhcpData == null) {
                  return const LuciLoadingWidget();
                }

                if (dashboardError != null && dhcpData == null) {
                  return LuciErrorDisplay(
                    title: 'Failed to Load Clients',
                    message: 'Could not connect to the router. Please check your network connection and the router\'s IP address.',
                    actionLabel: 'Retry',
                    onAction: () => appState.fetchDashboardData(),
                    icon: Icons.wifi_off_rounded,
                  );
                }

                final leases = dhcpData?['dhcp_leases'] as List<dynamic>? ?? [];
                final clients = leases.map((lease) {
                  final client = Client.fromLease(lease as Map<String, dynamic>);
                  final clientMac = normalizeMac(client.macAddress);
                  final isWireless = wirelessMacs.any((mac) => normalizeMac(mac) == clientMac);
                  return client.copyWith(connectionType: isWireless ? ConnectionType.wireless : ConnectionType.wired);
                }).toList();

                // Sort: wireless > wired > unknown, then by hostname
                clients.sort((a, b) {
                  int typeOrder(ConnectionType t) {
                    switch (t) {
                      case ConnectionType.wireless: return 0;
                      case ConnectionType.wired: return 1;
                      default: return 2;
                    }
                  }
                  final cmpType = typeOrder(a.connectionType).compareTo(typeOrder(b.connectionType));
                  if (cmpType != 0) return cmpType;
                  return a.hostname.toLowerCase().compareTo(b.hostname.toLowerCase());
                });

                final filteredClients = clients.where((client) {
                  final query = _searchQuery.toLowerCase();
                  return client.hostname.toLowerCase().contains(query) ||
                      client.ipAddress.toLowerCase().contains(query) ||
                      client.macAddress.toLowerCase().contains(query) ||
                      (client.vendor != null && client.vendor!.toLowerCase().contains(query)) ||
                      (client.dnsName != null && client.dnsName!.toLowerCase().contains(query));
                }).toList();

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: TextField(
                        autofocus: false,
                        onChanged: (value) {
                          // No need to setState here, listener handles it
                        },
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by name, IP, MAC, vendor...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      _searchController.clear();
                                    });
                                  },
                                  tooltip: 'Clear search',
                                )
                              : null,
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24.0),
                            borderSide: BorderSide.none,
                          ),
                          hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: filteredClients.isEmpty
                          ? LuciEmptyState(
                              title: _searchQuery.isEmpty ? 'No Active Clients Found' : 'No Matching Clients',
                              message: _searchQuery.isEmpty 
                                  ? 'No clients are currently connected to the router. Pull down to refresh the list.'
                                  : 'No clients match your search criteria. Try a different search term.',
                              icon: Icons.people_outline,
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.only(bottom: 16),
                              separatorBuilder: (context, idx) => const SizedBox(height: 4),
                              itemCount: filteredClients.length,
                              itemBuilder: (context, index) {
                                final client = filteredClients[index];
                                final isExpanded = _expandedClientIndex == index;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                  child: _UnifiedClientCard(
                                    client: client,
                                    isExpanded: isExpanded,
                                    onTap: () {
                                      setState(() {
                                        if (isExpanded) {
                                          _expandedClientIndex = null;
                                          _controller.reverse();
                                        } else {
                                          _expandedClientIndex = index;
                                          _controller.forward();
                                        }
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  String normalizeMac(String mac) => mac.toUpperCase().replaceAll('-', ':');
}

class _UnifiedClientCard extends StatefulWidget {
  final Client client;
  final bool isExpanded;
  final VoidCallback onTap;

  const _UnifiedClientCard({
    required this.client,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  State<_UnifiedClientCard> createState() => _UnifiedClientCardState();
}

class _UnifiedClientCardState extends State<_UnifiedClientCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    if (widget.isExpanded) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_UnifiedClientCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Card(
      elevation: widget.isExpanded ? 6 : 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
        side: BorderSide(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedScale(
        scale: widget.isExpanded ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: Column(
          children: [
            InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(18.0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                          child: AnimatedScale(
                            scale: widget.isExpanded ? 1.1 : 1.0,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.elasticOut,
                            child: Icon(
                              Icons.person_outline,
                              color: colorScheme.primary,
                              size: 22,
                              semanticLabel: 'Client icon',
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Tooltip(
                            message: widget.client.connectionType == ConnectionType.unknown
                                ? 'Unknown connection type'
                                : 'Client is online',
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: widget.client.connectionType == ConnectionType.wireless || widget.client.connectionType == ConnectionType.wired
                                    ? Colors.green
                                    : Colors.amber,
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
                            widget.client.hostname,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                            semanticsLabel: 'Client hostname: ${widget.client.hostname}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                            _buildMinimalClientSubtitle(widget.client),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.1,
                            ),
                            semanticsLabel: 'Client details: ${_buildMinimalClientSubtitle(widget.client)}',
                          ),
                          if (widget.client.vendor != null && widget.client.vendor!.isNotEmpty)
                            Text(
                              widget.client.vendor!,
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.7)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              semanticsLabel: 'Vendor: ${widget.client.vendor}',
                            ),
                        ],
                      ),
                    ),
                    _buildConnectionTypeChip(context, widget.client.connectionType),
                    const SizedBox(width: 8),
                    Icon(
                      widget.isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: colorScheme.onSurfaceVariant,
                      size: 26,
                      semanticLabel: widget.isExpanded ? 'Collapse details' : 'Expand details',
                    ),
                  ],
                ),
              ),
            ),
            if (widget.isExpanded)
              Column(
                children: [
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _buildClientDetails(context, widget.client),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionTypeChip(BuildContext context, ConnectionType type) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    String label;
    IconData icon;
    Color bgColor;
    Color fgColor;

    switch (type) {
      case ConnectionType.wireless:
        label = 'Wi-Fi';
        icon = Icons.wifi;
        bgColor = colorScheme.primaryContainer;
        fgColor = colorScheme.onPrimaryContainer;
        break;
      case ConnectionType.wired:
        label = 'Wired';
        icon = Icons.settings_ethernet;
        bgColor = colorScheme.secondaryContainer;
        fgColor = colorScheme.onSecondaryContainer;
        break;
      default:
        label = 'Unknown';
        icon = Icons.devices_other_outlined;
        bgColor = colorScheme.surfaceContainerHighest;
        fgColor = colorScheme.onSurfaceVariant;
        break;
    }

    return Chip(
      label: Text(label),
      avatar: Icon(icon, size: 16, color: fgColor),
      backgroundColor: bgColor,
      labelStyle: theme.textTheme.labelSmall?.copyWith(color: fgColor),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildClientDetails(BuildContext context, Client client) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    Widget detailRow(String title, String value, {Color? valueColor, VoidCallback? onTap, String? semanticsLabel}) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface), semanticsLabel: title),
              Row(
                children: [
                  Text(
                    value,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: valueColor ?? theme.colorScheme.onSurface,
                    ),
                    semanticsLabel: semanticsLabel ?? value,
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

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      child: Column(
        children: [
          detailRow('IP Address', client.ipAddress, onTap: () => _copyToClipboard(context, client.ipAddress, 'IP Address'), semanticsLabel: 'IP Address: ${client.ipAddress}'),
          if (client.ipv6Addresses != null && client.ipv6Addresses!.isNotEmpty)
            ...client.ipv6Addresses!.map((ipv6) => detailRow(
                  'IPv6 Address',
                  ipv6,
                  onTap: () => _copyToClipboard(context, ipv6, 'IPv6 Address'),
                  semanticsLabel: 'IPv6 Address: $ipv6',
                )),
          detailRow('MAC Address', client.macAddress, onTap: () => _copyToClipboard(context, client.macAddress, 'MAC Address'), semanticsLabel: 'MAC Address: ${client.macAddress}'),
          if (client.vendor != null && client.vendor!.isNotEmpty)
            detailRow('Vendor', client.vendor!, semanticsLabel: 'Vendor: ${client.vendor}'),
          if (client.dnsName != null && client.dnsName!.isNotEmpty)
            detailRow('DNS Name', client.dnsName!, semanticsLabel: 'DNS Name: ${client.dnsName}'),
          const Divider(height: 1, indent: 16, endIndent: 16),
          const SizedBox(height: 8),
          detailRow(
            'Lease Time Remaining',
            client.formattedLeaseTime,
            valueColor: client.formattedLeaseTime == 'Expired' ? theme.colorScheme.error : null,
            semanticsLabel: 'Lease Time Remaining: ${client.formattedLeaseTime}',
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _buildMinimalClientSubtitle(Client client) {
    final v4 = client.ipAddress;
    final v6s = client.ipv6Addresses ?? [];
    final v6 = v6s.isNotEmpty ? v6s.first : null;
    String? shown;
    int extra = 0;
    if (v4 != 'N/A') {
      shown = v4;
      if (v6 != null) extra++;
    } else if (v6 != null) {
      shown = v6;
    }
    if (shown == null) return '';
    if (extra > 0) {
      return '$shown  +$extra';
    } else {
      return shown;
    }
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard'), duration: const Duration(seconds: 2)),
    );
  }
}
