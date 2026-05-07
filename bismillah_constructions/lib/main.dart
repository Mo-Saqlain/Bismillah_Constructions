import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/app_restart.dart';
import 'core/constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Log Flutter framework errors (null dereferences, layout overflows, etc.)
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  // Catch errors thrown outside the Flutter widget tree (async callbacks, etc.)
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
    return true; // mark handled so the app doesn't crash
  };

  if (SupabaseConfig.configured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  }

  // Replace the default red crash screen with a compact error card.
  ErrorWidget.builder = (details) => _ErrorCard(message: details.exceptionAsString());

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

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Something went wrong',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.red),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}
