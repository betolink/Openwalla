import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/screens/splash_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AppState>(context, listen: false).fetchDashboardData();
    });
  }

  String _formatUptime(int seconds) {
    final duration = Duration(seconds: seconds);
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0 || days > 0) parts.add('${hours}h');
    parts.add('${minutes}m');
    return parts.join(' ');
  }

  String _formatCpuLoad(List<dynamic> load) {
    if (load.isEmpty) return 'N/A';
    // Use the first value as the main CPU load
    final percent = ((load[0] / 65536) * 100).clamp(0, 100);
    return '${percent.toStringAsFixed(0)}%';
  }

  Widget _buildDeviceInfoCard(AppState appState) {
    final boardInfo = appState.dashboardData?['boardInfo'] as Map<String, dynamic>?;
    final model = boardInfo?['model'] ?? 'N/A';
    final version = boardInfo?['release']?['version'] ?? 'N/A';
    final isSnapshot = boardInfo?['release']?['revision']?.toString().contains('SNAPSHOT') == true;
    final branch = isSnapshot ? 'SNAPSHOT' : 'stable';

    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        );
    final valueStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
        );

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Model', style: labelStyle),
                  const SizedBox(height: 4),
                  Text(model, style: valueStyle, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                ],
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Version', style: labelStyle),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(version, style: valueStyle, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSnapshot ? Colors.orange.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          branch,
                          style: TextStyle(
                            color: isSnapshot ? Colors.orange.shade800 : Colors.green.shade800,
                            fontWeight: FontWeight.bold,
                            fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRealtimeThroughputCard(AppState appState) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSpeedIndicator(Icons.arrow_downward, Colors.green, '', appState.currentRxRate),
                _buildSpeedIndicator(Icons.arrow_upward, Colors.blue, '', appState.currentTxRate),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (LineBarSpot spot) => Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                    tooltipBorderRadius: BorderRadius.circular(8),
                    tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    getTooltipItems: (List<LineBarSpot> touchedSpots) {
                      return touchedSpots.map((barSpot) {
                        final flSpot = barSpot;
                        final Color color = flSpot.bar.gradient?.colors.first ?? flSpot.bar.color ?? Colors.white;

                        return LineTooltipItem(
                          _formatSpeed(flSpot.y),
                          TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                          ),
                          textAlign: TextAlign.left,
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  _buildLineChartBarData(appState.rxHistory, [Colors.green.shade700, Colors.green.shade400]),
                  _buildLineChartBarData(appState.txHistory, [Colors.blue.shade700, Colors.blue.shade400]),
                ],
              ),
              duration: const Duration(milliseconds: 150),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedIndicator(IconData icon, Color color, String label, double speed) {
    final speedText = Text(_formatSpeed(speed), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        if (label.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              speedText,
            ],
          )
        else
          speedText,
      ],
    );
  }

  LineChartBarData _buildLineChartBarData(List<double> data, List<Color> gradientColors) {
    return LineChartBarData(
      spots: data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
      isCurved: true,
      gradient: LinearGradient(colors: gradientColors),
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: gradientColors.map((color) => color.withValues(alpha: 0.3)).toList(),
        ),
      ),
    );
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) return '${bytesPerSecond.toStringAsFixed(1)} B/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  // Consistent card builder for all dashboard vitals and summary cards
  Widget _buildVitalsColumn(BuildContext context, {required String label, required String value}) {
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        );
    final valueStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 4),
        Text(value, style: valueStyle, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildSystemVitalsCard(AppState appState) {
    final sysInfo = appState.dashboardData?['sysInfo'] as Map<String, dynamic>?;

    final uptime = sysInfo?['uptime'] as int?;
    final uptimeValue = uptime != null ? _formatUptime(uptime) : 'N/A';

    final cpuLoad = sysInfo?['load'] as List<dynamic>?;
    final cpuLoadValue = cpuLoad != null ? _formatCpuLoad(cpuLoad) : 'N/A';

    final totalMem = sysInfo?['memory']?['total'] as int? ?? 0;
    final freeMem = sysInfo?['memory']?['free'] as int? ?? 0;
    final bufferedMem = sysInfo?['memory']?['buffered'] as int? ?? 0;
    final usedMem = totalMem - freeMem - bufferedMem;
    final memoryValue = totalMem > 0 ? '${(usedMem / totalMem * 100).toStringAsFixed(0)}%' : 'N/A';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
        child: Row(
          children: [
            Expanded(
              child: _buildVitalsColumn(context, label: 'CPU Load', value: cpuLoadValue),
            ),
            Expanded(
              child: _buildVitalsColumn(context, label: 'Memory', value: memoryValue),
            ),
            Expanded(
              child: _buildVitalsColumn(context, label: 'Uptime', value: uptimeValue),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWirelessInfoCardContent(
    BuildContext context, {
    required String ssid,
    required bool isEnabled,
    required int? signal,
    required String channel,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi,
              color: isEnabled ? primaryColor : Colors.grey,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              ssid,
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            if (signal != null)
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.network_cell, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text('$signal dBm', style: textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            if (signal != null) const SizedBox(width: 8),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.settings_input_antenna, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text('Ch: $channel', style: textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWirelessNetworksCard(AppState appState) {
    final wirelessRadios = appState.dashboardData?['wireless'] as Map<String, dynamic>?;
    if (wirelessRadios == null || wirelessRadios.isEmpty) {
      return const SizedBox.shrink();
    }

    List<Widget> networkCardWidgets = [];
    wirelessRadios.forEach((radioName, radioData) {
      final interfaces = radioData['interfaces'] as List<dynamic>?;
      if (interfaces != null) {
        for (var interface in interfaces) {
          final config = interface['config'] ?? {};
          final iwinfo = interface['iwinfo'] ?? {};
          final ssid = iwinfo['ssid'] ?? config['ssid'] ?? 'N/A';
          if (ssid == 'N/A') continue;

          final isEnabled = !(config['disabled'] as bool? ?? false);
          final channel = (iwinfo['channel'] ?? config['channel'] ?? 'N/A').toString();
          final signal = iwinfo['signal'] as int?;

          networkCardWidgets.add(
            Card(
              margin: EdgeInsets.zero,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: _buildWirelessInfoCardContent(
                  context,
                  ssid: ssid,
                  isEnabled: isEnabled,
                  signal: signal,
                  channel: channel,
                ),
              ),
            ),
          );
        }
      }
    });

    if (networkCardWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    List<Widget> rowChildren = [];
    final isScrollable = networkCardWidgets.length > 2;
    for (int i = 0; i < networkCardWidgets.length; i++) {
      if (isScrollable) {
        rowChildren.add(SizedBox(width: 160, child: networkCardWidgets[i]));
      } else {
        rowChildren.add(Expanded(child: networkCardWidgets[i]));
      }
      if (i < networkCardWidgets.length - 1) {
        rowChildren.add(SizedBox(width: isScrollable ? 4 : 8));
      }
    }

    if (isScrollable) {
      return SizedBox(
        height: 110, // or whatever height fits the card
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: rowChildren,
        ),
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rowChildren,
      );
    }
  }

  IconData _getInterfaceIcon(String proto) {
    switch (proto) {
      case 'wireguard':
      case 'openvpn':
        return Icons.vpn_key_rounded;
      case 'pppoe':
      case 'dhcp':
      default:
        return Icons.public_rounded;
    }
  }

  Widget _buildInterfaceStatusCards(AppState appState) {
    final interfaces = appState.dashboardData?['interfaceDump']?['interface'] as List<dynamic>?;
    if (interfaces == null || interfaces.isEmpty) {
      return const SizedBox.shrink();
    }

    final wanVpnInterfaces = interfaces.where((item) {
      final interface = item as Map<String, dynamic>;
      final name = interface['interface'] as String? ?? '';
      final proto = interface['proto'] as String? ?? '';
      return name.startsWith('wan') || proto == 'pppoe' || proto == 'wireguard' || proto == 'openvpn';
    }).toList();

    if (wanVpnInterfaces.isEmpty) {
      return const SizedBox.shrink();
    }

    List<Widget> interfaceCardWidgets = [];
    for (var item in wanVpnInterfaces) {
      final interface = item as Map<String, dynamic>;
      final name = interface['interface'] as String? ?? 'N/A';
      final isUp = interface['up'] as bool? ?? false;
      final proto = interface['proto'] as String? ?? '';

      interfaceCardWidgets.add(
        Card(
          margin: EdgeInsets.zero,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.hardEdge,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 0.0, horizontal: 12.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(_getInterfaceIcon(proto), color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(height: 4),
                Text(
                  name.toUpperCase(),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isUp ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SizedBox(
                    width: 63,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(isUp ? Icons.check_circle : Icons.cancel, size: 11, color: isUp ? Colors.green.shade800 : Colors.red.shade800),
                          const SizedBox(width: 1),
                          Text(
                            isUp ? 'UP' : 'DOWN',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isUp ? Colors.green.shade900 : Colors.red.shade900,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    List<Widget> rowChildren = [];
    final isScrollable = interfaceCardWidgets.length >= 5;
    double? cardWidth;
    if (isScrollable) {
      // We'll calculate cardWidth in the LayoutBuilder below
    }
    for (int i = 0; i < interfaceCardWidgets.length; i++) {
      if (isScrollable && cardWidth != null) {
        rowChildren.add(SizedBox(width: cardWidth, child: interfaceCardWidgets[i]));
      } else {
        rowChildren.add(Expanded(child: interfaceCardWidgets[i]));
      }
      if (i < interfaceCardWidgets.length - 1) {
        rowChildren.add(const SizedBox(width: 12));
      }
    }

    if (isScrollable) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // 4 cards visible, 3 gaps between them
          final totalSpacing = 12.0 * 3;
          final width = constraints.maxWidth;
          final calculatedCardWidth = (width - totalSpacing) / 4;
          final localRowChildren = <Widget>[];
          for (int i = 0; i < interfaceCardWidgets.length; i++) {
            localRowChildren.add(SizedBox(width: calculatedCardWidth, child: interfaceCardWidgets[i]));
            if (i < interfaceCardWidgets.length - 1) {
              localRowChildren.add(const SizedBox(width: 12));
            }
          }
          return SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: localRowChildren,
            ),
          );
        },
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rowChildren,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final hostname = appState.dashboardData?['boardInfo']?['hostname'] ?? 'Loading...';
        return Scaffold(
          appBar: LuciAppBar(title: hostname.toString()),
          body: _buildBody(appState),
        );
      },
    );
  }

  Widget _buildBody(AppState appState) {
    if (appState.isDashboardLoading && appState.dashboardData == null) {
      return const SplashScreen();
    }

    if (appState.dashboardError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: ${appState.dashboardError}', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => appState.fetchDashboardData(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (appState.dashboardData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No data available.'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => appState.fetchDashboardData(),
              child: const Text('Fetch Data'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => appState.fetchDashboardData(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
          final content = [
            const SizedBox(height: 16),
            _buildDeviceInfoCard(appState),
            const SizedBox(height: 16),
            isLandscape
                ? SizedBox(height: 240, child: _buildRealtimeThroughputCard(appState))
                : Expanded(child: _buildRealtimeThroughputCard(appState)),
            const SizedBox(height: 16),
            _buildSystemVitalsCard(appState),
            const SizedBox(height: 16),
            _buildWirelessNetworksCard(appState),
            const SizedBox(height: 16),
            _buildInterfaceStatusCards(appState),
            const SizedBox(height: 16),
          ];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: isLandscape
                ? SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: content,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: content,
                  ),
          );
        },
      ),
    );
  }
}
