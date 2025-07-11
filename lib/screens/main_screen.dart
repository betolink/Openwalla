import 'package:flutter/material.dart';
import 'package:luci_mobile/screens/dashboard_screen.dart';
import 'package:luci_mobile/screens/clients_screen.dart';
import 'package:luci_mobile/screens/interfaces_screen.dart';
import 'package:luci_mobile/screens/more_screen.dart';

class MainScreen extends StatefulWidget {
  final int? initialTab;
  final String? interfaceToScroll;
  
  const MainScreen({super.key, this.initialTab, this.interfaceToScroll});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  String? _currentInterfaceToScroll;

  @override
  void initState() {
    super.initState();
    if (widget.initialTab != null) {
      _selectedIndex = widget.initialTab!;
    }
    _currentInterfaceToScroll = widget.interfaceToScroll;
  }

  void _clearInterfaceToScroll() {
    if (_currentInterfaceToScroll != null) {
      setState(() {
        _currentInterfaceToScroll = null;
      });
    }
  }

  List<Widget> get _widgetOptions => [
    const DashboardScreen(),
    const ClientsScreen(),
    InterfacesScreen(
      scrollToInterface: _currentInterfaceToScroll,
      onScrollComplete: _clearInterfaceToScroll,
    ),
    const MoreScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: _onItemTapped,
        selectedIndex: _selectedIndex,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            selectedIcon: Icon(Icons.dashboard),
            icon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.people),
            icon: Icon(Icons.people_outline),
            label: 'Clients',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.lan),
            icon: Icon(Icons.lan_outlined),
            label: 'Interfaces',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.more_horiz),
            icon: Icon(Icons.more_horiz_outlined),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
