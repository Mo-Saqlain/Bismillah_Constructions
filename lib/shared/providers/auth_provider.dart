import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bismillah_constructions/shared/data/models/app_user.dart';
import 'package:bismillah_constructions/shared/data/repositories/user_repository.dart';
import 'package:bismillah_constructions/shared/providers/db_providers.dart';
import 'package:bismillah_constructions/shared/providers/sync_providers.dart';

/// Provider for UserRepository
final userRepoProvider = FutureProvider<UserRepository>((ref) async {
  final db = await ref.watch(dbProvider.future);
  return UserRepository(db);
});

/// Bumping this version forces user list refetches across the app
final userVersionProvider = StateProvider<int>((ref) => 0);

/// Current logged in user notifier
class AuthStateNotifier extends StateNotifier<AsyncValue<AppUser?>> {
  AuthStateNotifier(this._ref) : super(const AsyncValue.loading()) {
    initFuture = _initSession();
    _ref.listen<int>(userVersionProvider, (_, __) => verifySession());
  }

  final Ref _ref;
  late final Future<void> initFuture;

  Future<void> _initSession() async {
    try {
      final repo = await _ref.read(userRepoProvider.future);
      final entityRepo = await _ref.read(entityRepoProvider.future);

      final keepLoggedIn = await entityRepo.getSetting('keep_me_logged_in');
      final activeUserId = await entityRepo.getSetting('active_user_id');

      if (keepLoggedIn == '1' && activeUserId != null && activeUserId.isNotEmpty) {
        final user = await repo.getUserById(activeUserId);
        if (user != null && user.isActive) {
          state = AsyncValue.data(user);
          return;
        }
      }

      // Default: no user logged in (ensure active_user_id cleared if keep_me_logged_in was not set)
      if (activeUserId != null && activeUserId.isNotEmpty) {
        await entityRepo.setSetting('active_user_id', '');
      }
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<bool> login(String username, String password, {bool keepLoggedIn = false}) async {
    state = const AsyncValue.loading();
    try {
      final repo = await _ref.read(userRepoProvider.future);
      final user = await repo.validateCredentials(username, password);

      if (user == null) {
        state = const AsyncValue.data(null);
        throw Exception('Invalid username or password.');
      }

      if (!user.isActive) {
        state = const AsyncValue.data(null);
        throw Exception('Your account access has been revoked or deleted. Contact administrator.');
      }

      // Persist session
      final entityRepo = await _ref.read(entityRepoProvider.future);
      await entityRepo.setSetting('active_user_id', user.id);
      await entityRepo.setSetting('keep_me_logged_in', keepLoggedIn ? '1' : '0');

      state = AsyncValue.data(user);
      return true;
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      final entityRepo = await _ref.read(entityRepoProvider.future);
      await entityRepo.setSetting('active_user_id', '');
      await entityRepo.setSetting('keep_me_logged_in', '0');
    } catch (_) {}
    state = const AsyncValue.data(null);
  }

  Future<void> verifySession() async {
    final current = state.valueOrNull;
    if (current == null) return;
    try {
      final repo = await _ref.read(userRepoProvider.future);
      final fresh = await repo.getUserById(current.id);
      if (fresh == null || !fresh.isActive) {
        await logout();
      } else if (fresh.username != current.username ||
          fresh.role != current.role ||
          fresh.status != current.status ||
          fresh.isDeleted != current.isDeleted) {
        state = AsyncValue.data(fresh);
      }
    } catch (_) {}
  }

  void refreshUser(AppUser updated) {
    state = AsyncValue.data(updated);
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthStateNotifier, AsyncValue<AppUser?>>((ref) {
  return AuthStateNotifier(ref);
});

/// Easy accessor for current logged in AppUser
final currentUserProvider = Provider<AppUser?>((ref) {
  return ref.watch(authNotifierProvider).valueOrNull;
});

/// Pending access requests count provider
final pendingRequestsCountProvider = FutureProvider<int>((ref) async {
  ref.watch(userVersionProvider);
  // Also watch cloud data changes so new sync pulls update pending count live
  ref.watch(remoteRefreshWiringProvider);
  final repo = await ref.watch(userRepoProvider.future);
  return repo.getPendingRequestsCount();
});
