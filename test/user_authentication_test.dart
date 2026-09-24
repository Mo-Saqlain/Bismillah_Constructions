import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bismillah_constructions/shared/data/db/local_db.dart';
import 'package:bismillah_constructions/shared/data/repositories/entity_repository.dart';
import 'package:bismillah_constructions/shared/data/repositories/user_repository.dart';
import 'package:bismillah_constructions/shared/providers/providers.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late UserRepository userRepo;

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 22,
        onCreate: (d, v) async {
      await LocalDb.instance.applySchemaForTests(d);
    });
    userRepo = UserRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('Superuser admin account is seeded on schema creation', () async {
    final admin = await userRepo.getUserByUsername('admin');
    expect(admin, isNotNull);
    expect(admin!.username, equals('admin'));
    expect(admin.role, equals('admin'));

    final valid = await userRepo.validateCredentials('admin', 'Tech@123');
    expect(valid, isNotNull);
    expect(valid!.id, equals(admin.id));

    final invalid = await userRepo.validateCredentials('admin', 'WrongPass');
    expect(invalid, isNull);
  });

  test('User creation and validation flow', () async {
    final newUser = await userRepo.createUser(
      username: 'site_supervisor',
      password: 'SuperPassword123',
      role: 'user',
    );

    expect(newUser.username, equals('site_supervisor'));
    expect(newUser.role, equals('user'));

    final authenticated =
        await userRepo.validateCredentials('site_supervisor', 'SuperPassword123');
    expect(authenticated, isNotNull);
    expect(authenticated!.id, equals(newUser.id));
  });

  test('Access request creation and approval workflow', () async {
    final req = await userRepo.createAccessRequest(
      username: 'new_contractor',
      fullName: 'Tariq Mahmood',
      phoneOrEmail: '0300-9998877',
    );

    expect(req.username, equals('new_contractor'));
    expect(req.status, equals('pending'));

    final count = await userRepo.getPendingRequestsCount();
    expect(count, equals(1));

    // Admin approves request
    await userRepo.createUser(
      username: req.username,
      password: 'ApprovedPassword!1',
      role: 'user',
    );
    await userRepo.updateAccessRequestStatus(req.id, 'approved');

    final remainingCount = await userRepo.getPendingRequestsCount();
    expect(remainingCount, equals(0));

    final user =
        await userRepo.validateCredentials('new_contractor', 'ApprovedPassword!1');
    expect(user, isNotNull);
  });

  test('Revoking user access prevents login', () async {
    final user = await userRepo.createUser(
      username: 'sub_user',
      password: 'SecretPassword',
    );

    expect(user.status, equals('active'));

    // Admin revokes access
    await userRepo.updateUserStatus(user.id, 'revoked');

    final updated = await userRepo.getUserByUsername('sub_user');
    expect(updated!.status, equals('revoked'));
    expect(updated.isActive, isFalse);
  });

  test('Session persistence respects keep_me_logged_in flag', () async {
    final entityRepo = EntityRepository(db);

    // 1. Login with keepLoggedIn = false
    final container1 = ProviderContainer(
      overrides: [
        dbProvider.overrideWith((ref) async => db),
      ],
    );
    final notifier1 = container1.read(authNotifierProvider.notifier);
    await notifier1.login('admin', 'Tech@123', keepLoggedIn: false);

    expect(container1.read(currentUserProvider)?.username, equals('admin'));
    expect(await entityRepo.getSetting('keep_me_logged_in'), equals('0'));

    // Simulate restart with keepLoggedIn = false -> should be unauthenticated
    final container2 = ProviderContainer(
      overrides: [
        dbProvider.overrideWith((ref) async => db),
      ],
    );
    await container2.read(authNotifierProvider.notifier).initFuture;
    expect(container2.read(currentUserProvider), isNull);

    // 2. Login with keepLoggedIn = true
    final notifier2 = container2.read(authNotifierProvider.notifier);
    await notifier2.login('admin', 'Tech@123', keepLoggedIn: true);
    expect(await entityRepo.getSetting('keep_me_logged_in'), equals('1'));

    // Simulate restart with keepLoggedIn = true -> should auto-authenticate
    final container3 = ProviderContainer(
      overrides: [
        dbProvider.overrideWith((ref) async => db),
      ],
    );
    await container3.read(authNotifierProvider.notifier).initFuture;
    expect(container3.read(currentUserProvider)?.username, equals('admin'));

    container1.dispose();
    container2.dispose();
    container3.dispose();
  });

  test('Auto-logout executes immediately when active user status becomes revoked', () async {
    final container = ProviderContainer(
      overrides: [
        dbProvider.overrideWith((ref) async => db),
      ],
    );
    addTearDown(container.dispose);

    final subUser = await userRepo.createUser(
      username: 'active_field_worker',
      password: 'WorkerPassword123',
    );

    final notifier = container.read(authNotifierProvider.notifier);
    await notifier.login('active_field_worker', 'WorkerPassword123', keepLoggedIn: true);
    expect(container.read(currentUserProvider)?.id, equals(subUser.id));

    // Admin revokes access
    await userRepo.updateUserStatus(subUser.id, 'revoked');

    // Trigger session verification
    await notifier.verifySession();

    // User is automatically logged out
    expect(container.read(currentUserProvider), isNull);
  });

  test('Wiping database automatically re-seeds superuser admin account', () async {
    // Delete all app_users directly to simulate wipe
    await db.delete('app_users');
    final admin = await userRepo.getUserByUsername('admin');
    expect(admin, isNotNull);
    expect(admin!.username, equals('admin'));

    final valid = await userRepo.validateCredentials('admin', 'Tech@123');
    expect(valid, isNotNull);
    expect(valid!.username, equals('admin'));
  });
}
