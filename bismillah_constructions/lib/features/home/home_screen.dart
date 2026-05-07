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

  late final PageController _pageController =
      PageController(initialPage: _homeIndex);

  // 4 destinations in order: Home, Manage, Reports, Settings.
  // Projects, Suppliers, Banks/Wallets and Material Types all live inside
  // the Manage tab so the bottom bar stays at four slots.
  static const _tabs = <Widget>[
    DashboardScreen(),
    ManageScreen(),
    ReportsScreen(),
    SettingsScreen(),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToTab(int i) {
    if (i == _index) return;
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
    );
  }

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
        if (!onHome) _goToTab(_homeIndex);
      },
      child: Scaffold(
        body: PageView(
          controller: _pageController,
          // Default PageScrollPhysics enables horizontal swipe between tabs.
          // A pushed sub-screen (e.g. tapping a tile) lives on the root
          // Navigator above this PageView, so its swipes do not affect tabs.
          onPageChanged: (i) => setState(() => _index = i),
          children: _tabs.map((w) => _KeepAlivePage(child: w)).toList(),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _goToTab,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune),
                label: 'Manage'),
            NavigationDestination(
                icon: Icon(Icons.assessment_outlined),
                selectedIcon: Icon(Icons.assessment),
                label: 'Reports'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings'),
          ],
        ),
      ),
    );
  }
}

/// Wraps a tab page in an [AutomaticKeepAliveClientMixin] state so PageView
/// doesn't rebuild it when the user swipes away — this preserves scroll
/// position, form input, etc. across tab transitions, matching the previous
/// IndexedStack behaviour.
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});
  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
