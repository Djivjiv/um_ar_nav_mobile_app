import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:um_ar_mobile_app/core/config/email_role_config.dart';
import 'package:um_ar_mobile_app/core/config/required_keys.dart';
import 'package:um_ar_mobile_app/data/models/user_profile_model.dart';
import 'package:um_ar_mobile_app/data/repositories/auth_repository.dart';
import 'package:um_ar_mobile_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:um_ar_mobile_app/presentation/routes/app_router.dart';
import 'package:um_ar_mobile_app/presentation/screens/auth/account_status_screen.dart';
import 'package:um_ar_mobile_app/presentation/screens/setup/setup_required_screen.dart';

const studentEmail = 'j.delacruz.123456@umindanao.edu.ph';
const otherEmail = 'juan.delacruz@umindanao.edu.ph';

UserProfileModel profile({
  String? role = 'student',
  bool verified = true,
  bool active = true,
  String email = studentEmail,
}) =>
    UserProfileModel(
      id: 'u1',
      email: email,
      role: role,
      isVerified: verified,
      isActive: active,
    );

class FakeAuthRepository implements AuthRepository {
  UserProfileModel? stored;
  GoogleSignInResult? google;
  bool signedOut = false;

  FakeAuthRepository({this.stored, this.google});

  @override
  Future<GoogleSignInResult> signInWithGoogle() async => google!;
  @override
  Future<bool> hasValidTimedSession() async => true;
  @override
  Future<UserProfileModel?> getProfile() async => stored;
  @override
  Future<UserProfileModel?> updateRole(String role) async => stored;
  @override
  Future<void> signOut() async => signedOut = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('student email format', () {
    test('first initial.lastname.idnumber is a student', () {
      for (final email in [
        studentEmail,
        'J.DelaCruz.123456@UMindanao.edu.ph',
        '  j.cruz.1@umindanao.edu.ph ',
        'm.santos-reyes.555123@umindanao.edu.ph',
      ]) {
        expect(EmailRoleConfig.classify(email), SchoolEmailKind.student,
            reason: email);
      }
    });

    test('anything else is not', () {
      for (final email in [
        otherEmail,
        'juan.delacruz.123456@umindanao.edu.ph', // full first name
        'j.delacruz@umindanao.edu.ph', // no id number
        'j.delacruz.12a456@umindanao.edu.ph',
        'j.dela.cruz.123456@umindanao.edu.ph',
        'j.delacruz.123456@gmail.com',
        'j.delacruz.123456@umindanao.edu.ph.evil.com',
        'x j.delacruz.123456@umindanao.edu.ph',
        '',
        null,
      ]) {
        expect(EmailRoleConfig.classify(email), SchoolEmailKind.other,
            reason: '$email');
      }
    });

    test('a confirmed faculty format wins over the student one', () {
      final faculty = RegExp(r'^[a-z]\.[a-z]+\.9[0-9]+@umindanao\.edu\.ph$');
      expect(
          EmailRoleConfig.classify('j.cruz.9001@umindanao.edu.ph',
              faculty: faculty),
          SchoolEmailKind.faculty);
      expect(EmailRoleConfig.classify(studentEmail, faculty: faculty),
          SchoolEmailKind.student);
    });

    test('no faculty format is set until it is confirmed', () {
      expect(EmailRoleConfig.facultyPattern, isNull);
    });
  });

  group('the first Google sign-in', () {
    UserProfileModel first(String email) =>
        AuthRepository.firstGoogleProfile(id: 'u1', email: email);

    test('student format: a verified student, no questions', () {
      final p = first(studentEmail);
      expect(p.role, 'student');
      expect(p.isVerified, isTrue);
      expect(p.access, AccountAccess.allowed);
    });

    test('any other school email: asks for a role, unverified', () {
      final p = first(otherEmail);
      expect(p.role, isNull);
      expect(p.isVerified, isFalse);
      expect(p.access, AccountAccess.needsRole);
    });
  });

  group('account access', () {
    test('verified and active can use the app', () {
      for (final role in ['student', 'faculty', 'employee']) {
        expect(profile(role: role).access, AccountAccess.allowed, reason: role);
      }
    });

    test('unverified with a role is pending, whatever the role', () {
      for (final role in ['student', 'faculty', 'employee', 'visitor']) {
        expect(profile(role: role, verified: false).access,
            AccountAccess.pending,
            reason: role);
      }
    });

    test('no role yet asks for one, also when verified', () {
      expect(profile(role: null).access, AccountAccess.needsRole);
      expect(profile(role: ' ', verified: false).access,
          AccountAccess.needsRole);
    });

    test('rejected is unverified and inactive; inactive was verified', () {
      expect(profile(verified: false, active: false).access,
          AccountAccess.rejected);
      expect(profile(active: false).access, AccountAccess.inactive);
    });

    test('inactive beats everything, also an admin or a missing role', () {
      expect(profile(role: 'admin', active: false).access,
          AccountAccess.inactive);
      expect(profile(role: null, verified: false, active: false).access,
          AccountAccess.rejected);
    });

    test('an admin does not wait for approval', () {
      expect(profile(role: 'admin', verified: false).access,
          AccountAccess.allowed);
    });

    test('rows without the columns read safely', () {
      final p = UserProfileModel.fromMap({'id': 'u1', 'role': 'student'});
      expect(p.access, AccountAccess.pending, reason: 'never verified');
    });
  });

  group('AuthCubit', () {
    AuthCubit cubit(FakeAuthRepository repo) => AuthCubit(repo);

    Future<AuthState> signIn(UserProfileModel p, FakeAuthRepository repo) async {
      repo.google = GoogleSignInResult(GoogleSignInStatus.success, profile: p);
      final c = cubit(repo);
      await c.signInWithGoogle();
      return c.state;
    }

    test('an allowed account is authenticated, and stays signed in', () async {
      final repo = FakeAuthRepository();
      expect(await signIn(profile(), repo), isA<AuthAuthenticated>());
      expect(repo.signedOut, isFalse);
    });

    test('a pending account is held, but stays signed in to check again',
        () async {
      final repo = FakeAuthRepository();
      final s = await signIn(profile(verified: false), repo);
      expect((s as AuthAccountBlocked).access, AccountAccess.pending);
      expect(repo.signedOut, isFalse);
    });

    test('a rejected account is blocked and signed out', () async {
      final repo = FakeAuthRepository();
      final s = await signIn(profile(verified: false, active: false), repo);
      expect((s as AuthAccountBlocked).access, AccountAccess.rejected);
      expect(repo.signedOut, isTrue);
    });

    test('an inactive account is blocked and signed out', () async {
      final repo = FakeAuthRepository();
      final s = await signIn(profile(active: false), repo);
      expect((s as AuthAccountBlocked).access, AccountAccess.inactive);
      expect(repo.signedOut, isTrue);
    });

    test('a blocked account is not let in by restoring its session', () async {
      for (final p in [
        profile(verified: false),
        profile(active: false),
        profile(verified: false, active: false),
      ]) {
        final c = cubit(FakeAuthRepository(stored: p));
        await c.tryRestoreTimedSession();
        expect(c.state, isA<AuthAccountBlocked>());
      }
    });

    test('picking a role leaves the account pending', () async {
      final repo = FakeAuthRepository(
          stored: profile(role: 'faculty', verified: false, email: otherEmail));
      repo.google = GoogleSignInResult(GoogleSignInStatus.success,
          profile: profile(role: null, verified: false, email: otherEmail));
      final c = cubit(repo);
      await c.signInWithGoogle();
      expect(c.state, isA<AuthNeedsRoleSelection>());

      await c.selectRole('faculty');
      expect((c.state as AuthAccountBlocked).access, AccountAccess.pending);
    });

    test('approval is picked up on the next check', () async {
      final repo = FakeAuthRepository();
      final c = cubit(repo);
      repo.google = GoogleSignInResult(GoogleSignInStatus.success,
          profile: profile(verified: false));
      await c.signInWithGoogle();

      repo.stored = profile();
      await c.recheckAccess();
      expect(c.state, isA<AuthAuthenticated>());
    });

    test('deactivation while the app is open takes effect on the next check',
        () async {
      final repo = FakeAuthRepository(stored: profile());
      final c = cubit(repo);
      await c.tryRestoreTimedSession();
      expect(c.state, isA<AuthAuthenticated>());

      repo.stored = profile(active: false);
      await c.recheckAccess();
      expect((c.state as AuthAccountBlocked).access, AccountAccess.inactive);
      expect(repo.signedOut, isTrue);
    });

    test('a check with no profile (offline, nothing saved) changes nothing',
        () async {
      final repo = FakeAuthRepository(stored: profile());
      final c = cubit(repo);
      await c.tryRestoreTimedSession();
      repo.stored = null;
      await c.recheckAccess();
      expect(c.state, isA<AuthAuthenticated>());
    });

    test('a visitor is not checked', () async {
      final c = cubit(FakeAuthRepository(stored: profile(active: false)));
      await c.recheckAccess();
      expect(c.state, isA<AuthInitial>());
    });
  });

  group('routing', () {
    final blocked = AuthAccountBlocked(
        AccountAccess.pending, profile(verified: false));

    test('a blocked account can reach only the status screen', () {
      for (final loc in ['/map', '/ar', '/places', '/login', '/survey']) {
        expect(AppRouter.blockedRedirect(blocked, loc), '/account-status');
      }
      expect(AppRouter.blockedRedirect(blocked, '/account-status'), isNull);
    });

    test('nobody else is redirected by it', () {
      expect(
          AppRouter.blockedRedirect(AuthAuthenticated(profile()), '/map'),
          isNull);
      expect(AppRouter.blockedRedirect(const AuthUnauthenticated(), '/map'),
          isNull);
    });
  });

  group('account status screen', () {
    Future<void> pump(WidgetTester tester, AccountAccess access) async {
      final repo = FakeAuthRepository();
      repo.google = GoogleSignInResult(GoogleSignInStatus.success,
          profile: switch (access) {
            AccountAccess.pending => profile(verified: false),
            AccountAccess.rejected => profile(verified: false, active: false),
            _ => profile(active: false),
          });
      final c = AuthCubit(repo);
      await c.signInWithGoogle();
      await tester.pumpWidget(BlocProvider.value(
        value: c,
        child: const MaterialApp(home: AccountStatusScreen()),
      ));
    }

    testWidgets('pending says so and can check again', (tester) async {
      await pump(tester, AccountAccess.pending);
      expect(find.text('Waiting for approval'), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);
    });

    testWidgets('rejected explains, with no way to check again',
        (tester) async {
      await pump(tester, AccountAccess.rejected);
      expect(find.text('Account not approved'), findsOneWidget);
      expect(find.text('Check again'), findsNothing);
      expect(find.text('Back to sign in'), findsOneWidget);
    });

    testWidgets('inactive explains, with no way to check again',
        (tester) async {
      await pump(tester, AccountAccess.inactive);
      expect(find.text('Account deactivated'), findsOneWidget);
      expect(find.text('Check again'), findsNothing);
    });
  });

  group('required keys', () {
    List<String> check({
      String url = 'https://example.supabase.co',
      String anon = 'anon',
      String map = 'map',
    }) =>
        missingKeys(supabaseUrl: url, supabaseAnonKey: anon, mapTilerKey: map);

    test('all present', () => expect(check(), isEmpty));

    test('each one is named when missing or blank', () {
      expect(check(url: ''), ['SUPABASE_URL']);
      expect(check(anon: ' '), ['SUPABASE_ANON_KEY']);
      expect(check(map: ''), ['MAPTILER_KEY']);
      expect(check(url: '', anon: '', map: ''),
          ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'MAPTILER_KEY']);
    });

    test('a URL that is not one counts as missing', () {
      expect(check(url: 'not a url'), ['SUPABASE_URL']);
      expect(check(url: 'example.supabase.co'), ['SUPABASE_URL']);
    });

    test('a test build has no keys in the source', () {
      expect(missingKeys(),
          ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'MAPTILER_KEY']);
    });

    testWidgets('the setup screen names what is missing', (tester) async {
      await tester.pumpWidget(
          const SetupRequiredApp(missing: ['MAPTILER_KEY']));
      expect(find.text('Setup required'), findsOneWidget);
      expect(find.text('MAPTILER_KEY'), findsOneWidget);
      expect(find.text('SUPABASE_URL'), findsNothing);
    });
  });
}
