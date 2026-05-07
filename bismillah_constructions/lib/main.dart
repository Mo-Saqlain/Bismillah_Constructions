import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/app_restart.dart';
import 'core/constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (SupabaseConfig.configured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  }

  // Wrapping ProviderScope in a ValueListenableBuilder keyed to
  // appRestartNotifier lets the auto-restore flow trigger a full
  // provider-tree teardown by calling restartApp(). The new ProviderScope
  // key causes every provider to rebuild from scratch against the freshly
  // restored database file.
  runApp(
    ValueListenableBuilder<int>(
      valueListenable: appRestartNotifier,
      builder: (context, count, child) => ProviderScope(
        key: ValueKey(count),
        child: const BismillahApp(),
      ),
    ),
  );
}
