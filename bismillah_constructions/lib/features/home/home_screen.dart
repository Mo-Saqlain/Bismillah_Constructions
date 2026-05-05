import 'package:flutter/material.dart';

import '../dashboard/dashboard_screen.dart';
import '../parties/parties_screen.dart';
import '../projects/projects_screen.dart';
import '../reports/reports_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  // 4 destinations: Home (Dashboard), Projects, Suppliers, Reports.
  // Customers were removed entirely (the client is just a text field on the
  // project). Banks/wallets are managed inside Settings.
  static const _tabs = <Widget>[
    DashboardScreen(),
    ProjectsScreen(),
    SuppliersScreen(),
    ReportsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.foundation_outlined),
              selectedIcon: Icon(Icons.foundation),
              label: 'Projects'),
          NavigationDestination(
              icon: Icon(Icons.local_shipping_outlined),
              selectedIcon: Icon(Icons.local_shipping),
              label: 'Suppliers'),
          NavigationDestination(
              icon: Icon(Icons.assessment_outlined),
              selectedIcon: Icon(Icons.assessment),
              label: 'Reports'),
        ],
      ),
    );
  }
}
