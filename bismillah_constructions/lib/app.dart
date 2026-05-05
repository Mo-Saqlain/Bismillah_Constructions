import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/home/home_screen.dart';
import 'providers/providers.dart';

class SoloConApp extends ConsumerWidget {
  const SoloConApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Eagerly start the sync service.
    ref.watch(syncServiceFutureProvider);
    // Cold-boot silent backup (>6h since last).
    ref.watch(backupBootCheckProvider);
    // Wire every transaction commit to a debounced cloud + Supabase sync.
    ref.watch(commitSyncWiringProvider);

    final mode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Solo-Con ERP',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: buildTheme(brightness: Brightness.light),
      darkTheme: buildTheme(brightness: Brightness.dark),
      home: const HomeScreen(),
    );
  }
}
