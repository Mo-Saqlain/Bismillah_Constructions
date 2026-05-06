import 'package:flutter/material.dart';

import '../dashboard/dashboard_screen.dart';
import '../manage/manage_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 0 is the Home (Dashboard) tab. The PopScope below treats it as the
  /// "root" — back from any other tab snaps here instead of exiting the app.
  static const _homeIndex = 0;
  int _index = _homeIndex;

  // 4 destinations: Home (Dashboard), Settings, Reports, Manage.
  // Projects, Suppliers, Banks/Wallets and Material Types all live inside
  // the Manage tab now so the bottom bar stays at four slots.
  static const _tabs = <Widget>[
    DashboardScreen(),
    SettingsScreen(),
    ReportsScreen(),
    ManageScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final onHome = _index == _homeIndex;
    // PopScope intercepts the system back gesture (Android hardware
    // button, swipe-back, etc.). When the user is on a non-Home tab
    // we swallow the pop and switch to the Home tab so they don't
    // accidentally drop out of the app from Settings/Manage/Reports.
    // On the Home tab we let the pop go through (which exits the app).
    return PopScope(
      canPop: onHome,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!onHome) setState(() => _index = _homeIndex);
      },
      child: Scaffold(
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
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings'),
            NavigationDestination(
                icon: Icon(Icons.assessment_outlined),
                selectedIcon: Icon(Icons.assessment),
                label: 'Reports'),
            NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune),
                label: 'Manage'),
          ],
        ),
      ),
    );
  }
}
