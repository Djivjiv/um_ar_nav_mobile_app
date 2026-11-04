import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:um_ar_mobile_app/core/utils/geofence_service.dart';
import 'package:um_ar_mobile_app/data/models/user_profile_model.dart';
import 'package:um_ar_mobile_app/data/repositories/repository_exception.dart';
import 'package:um_ar_mobile_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:um_ar_mobile_app/presentation/routes/app_router.dart';
import 'package:um_ar_mobile_app/presentation/screens/auth/account_status_screen.dart';
import 'package:um_ar_mobile_app/presentation/screens/auth/login_screen.dart';
import 'package:um_ar_mobile_app/presentation/screens/auth/role_selection_screen.dart';

import 'support/visitor_fakes.dart';

const newUser = UserProfileModel(id: 'u1', email: 'someone@umindanao.edu.ph');
const pending = UserProfileModel(
    id: 'u1', email: 'someone@umindanao.edu.ph', role: 'faculty');

/// The server's answers to `updateRole`, one per save.
class ScriptedAuth extends StubAuthRepository {
  final List<FutureOr<UserProfileModel?> Function()> answers;
  int saves = 0;
  ScriptedAuth(this.answers);

  @override
  Future<UserProfileModel?> updateRole(String role) async =>
      answers[saves++]();
}

class RoleCubit extends AuthCubit {
  RoleCubit(ScriptedAuth super.auth) {
    emit(const AuthNeedsRoleSelection(newUser));
  }
}

void main() {
  late GoRouter router;

  Future<RoleCubit> pumpRoleScreen(
      WidgetTester tester, ScriptedAuth auth) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cubit = RoleCubit(auth);
    await tester.pumpWidget(BlocProvider<AuthCubit>.value(
      value: cubit,
      child: Builder(builder: (context) {
        router = AppRouter.build(context, initialLocation: '/select-role');
        return MaterialApp.router(routerConfig: router);
      }),
    ));
    await tester.pumpAndSettle();
    return cubit;
  }

  Future<void> pickAndContinue(WidgetTester tester) async {
    await tester.tap(find.text('Faculty'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();
  }

  String location() => router.state.uri.toString();

  group('while the role is being saved', () {
    testWidgets('the user stays on the role screen, never /login',
        (tester) async {
      final answer = Completer<UserProfileModel?>();
      final auth = ScriptedAuth([() => answer.future]);
      await pumpRoleScreen(tester, auth);
      final seen = <String>[];
      router.routerDelegate.addListener(() => seen.add(location()));

      await pickAndContinue(tester);
      await tester.pump(const Duration(seconds: 2));

      expect(location(), '/select-role');
      expect(seen, isNot(contains('/login')));
      expect(find.byType(RoleSelectionScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      answer.complete(pending);
      await tester.pumpAndSettle();
    });

    testWidgets('the campus check stays valid', (tester) async {
      final answer = Completer<UserProfileModel?>();
      await pumpRoleScreen(tester, ScriptedAuth([() => answer.future]));
      GeofenceService.campusVerified = true;

      await pickAndContinue(tester);

      expect(GeofenceService.campusVerified, isTrue);

      answer.complete(pending);
      await tester.pumpAndSettle();
      GeofenceService.campusVerified = false;
    });

    testWidgets('a second tap does not save twice', (tester) async {
      final answer = Completer<UserProfileModel?>();
      final auth = ScriptedAuth([() => answer.future]);
      final cubit = await pumpRoleScreen(tester, auth);

      await pickAndContinue(tester);
      await cubit.selectRole('faculty');

      expect(auth.saves, 1);

      answer.complete(pending);
      await tester.pumpAndSettle();
    });
  });

  group('when the save fails', () {
    void expectErrorOnRoleScreen(String message) {
      expect(location(), '/select-role');
      expect(find.byType(RoleSelectionScreen), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    }

    testWidgets('the server refused: its message and Retry', (tester) async {
      await pumpRoleScreen(
          tester,
          ScriptedAuth([
            () => throw RepositoryException('Could not save your role: no')
          ]));

      await pickAndContinue(tester);
      await tester.pumpAndSettle();

      expectErrorOnRoleScreen('Could not save your role: no');
    });

    testWidgets('no connection: not stuck, and Retry', (tester) async {
      await pumpRoleScreen(tester,
          ScriptedAuth([() => throw const SocketException('no route')]));

      await pickAndContinue(tester);
      await tester.pumpAndSettle();

      expectErrorOnRoleScreen('Could not save your role. Please try again.');
    });

    testWidgets('no profile came back: Retry', (tester) async {
      await pumpRoleScreen(tester, ScriptedAuth([() => null]));

      await pickAndContinue(tester);
      await tester.pumpAndSettle();

      expectErrorOnRoleScreen('Could not save your role. Please try again.');
    });

    testWidgets('Retry saves the same role and moves on', (tester) async {
      final auth = ScriptedAuth([
        () => throw const SocketException('no route'),
        () => pending,
      ]);
      final cubit = await pumpRoleScreen(tester, auth);
      await pickAndContinue(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(auth.saves, 2);
      expect(cubit.state, isA<AuthAccountBlocked>());
      expect(location(), '/account-status');
      expect(find.byType(AccountStatusScreen), findsOneWidget);
    });

    testWidgets('a failed Retry shows the error again', (tester) async {
      final auth = ScriptedAuth([
        () => throw const SocketException('no route'),
        () => throw const SocketException('no route'),
      ]);
      await pumpRoleScreen(tester, auth);
      await pickAndContinue(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(auth.saves, 2);
      expectErrorOnRoleScreen('Could not save your role. Please try again.');
    });

    testWidgets('the error clears while saving again', (tester) async {
      final answer = Completer<UserProfileModel?>();
      await pumpRoleScreen(
          tester,
          ScriptedAuth([
            () => throw const SocketException('no route'),
            () => answer.future,
          ]));
      await pickAndContinue(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(find.text('Retry'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      answer.complete(pending);
      await tester.pumpAndSettle();
    });
  });

  group('the access rules are unchanged', () {
    test('a verified role is let in', () async {
      const verified = UserProfileModel(
          id: 'u1', role: 'student', isVerified: true);
      final cubit = RoleCubit(ScriptedAuth([() => verified]));

      await cubit.selectRole('student');

      expect(cubit.state, isA<AuthAuthenticated>());
    });

    test('an unverified role waits for an admin', () async {
      final cubit = RoleCubit(ScriptedAuth([() => pending]));

      await cubit.selectRole('faculty');

      final state = cubit.state as AuthAccountBlocked;
      expect(state.access, AccountAccess.pending);
    });

    test('a save in progress never counts as signed in or visitor', () {
      const saving = AuthNeedsRoleSelection(newUser, saving: true);

      expect(canSeeIndoorMap(saving), isFalse);
      expect(AppRouter.blockedRedirect(saving, '/select-role'), isNull);
    });
  });
}
