import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/device_utils.dart';
import '../../../core/utils/session_service.dart';
import '../../../data/models/user_profile_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/repository_exception.dart';

part 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final AuthRepository _repo;

  AuthCubit(this._repo) : super(const AuthInitial());

  AuthRepository get repo => _repo;

  void reset() => emit(const AuthUnauthenticated());

  /// Restores an authenticated state on launch when the 8-hour login window
  /// is still open and a Supabase session exists. Called from splash.
  Future<bool> tryRestoreTimedSession() async {
    final valid = await _repo.hasValidTimedSession();
    if (!valid) {
      await _repo.signOut();
      emit(const AuthUnauthenticated());
      return false;
    }
    final profile = await _repo.getProfile();
    if (profile == null) {
      await _repo.signOut();
      emit(const AuthUnauthenticated());
      return false;
    }
    emit(profile.hasRole
        ? AuthAuthenticated(profile)
        : AuthNeedsRoleSelection(profile));
    return true;
  }

  Future<void> signInWithGoogle() async {
    emit(const AuthLoading());
    final result = await _repo.signInWithGoogle();
    if (result.detail != null) {
      // Detailed diagnostics stay in the debug console only.
      debugPrint('Google Sign-In error: ${result.detail}');
    }
    switch (result.status) {
      case GoogleSignInStatus.success:
        final profile = result.profile!;
        emit(result.needsRoleSelection
            ? AuthNeedsRoleSelection(profile)
            : AuthAuthenticated(profile));
      case GoogleSignInStatus.cancelled:
        emit(const AuthUnauthenticated());
      case GoogleSignInStatus.wrongDomain:
        emit(const AuthError(
            'Only @umindanao.edu.ph accounts allowed'));
      case GoogleSignInStatus.networkError:
        emit(const AuthError('Connection failed. Check your internet'));
      case GoogleSignInStatus.failed:
        emit(const AuthError('Sign-in failed. Please try again.'));
    }
  }

  Future<void> selectRole(String role) async {
    final current = state;
    if (current is! AuthNeedsRoleSelection) return;
    emit(const AuthLoading());
    try {
      final profile = await _repo.updateRole(role);
      if (profile != null && profile.hasRole) {
        emit(AuthAuthenticated(profile));
      } else {
        emit(AuthNeedsRoleSelection(current.user));
        emit(const AuthError('Could not save your role. Please try again.'));
      }
    } on RepositoryException catch (e) {
      emit(AuthNeedsRoleSelection(current.user));
      emit(AuthError(e.message));
    }
  }

  Future<void> signIn(String email, String password) async {
    emit(const AuthLoading());
    try {
      final res = await _repo.signInWithEmail(email, password);
      if (res.needsEmailVerification) {
        emit(AuthNeedsVerification(email));
        return;
      }
      if (res.profile != null) {
        emit(AuthAuthenticated(res.profile!));
      } else {
        emit(const AuthError('Sign in failed. Please try again.'));
      }
    } on RepositoryException catch (e) {
      emit(AuthError(e.message));
    } catch (_) {
      emit(const AuthError('Something went wrong. Please try again.'));
    }
  }

  Future<void> register(
      String email, String password, String fullName) async {
    emit(const AuthLoading());
    try {
      await _repo.registerWithEmail(email, password, fullName);
      emit(AuthNeedsVerification(email));
    } on RepositoryException catch (e) {
      emit(AuthError(e.message));
    } catch (_) {
      emit(const AuthError('Registration failed. Please try again.'));
    }
  }

  Future<void> resendVerification(String email) async {
    try {
      await _repo.resendVerification(email);
    } on RepositoryException catch (e) {
      emit(AuthError(e.message));
    }
  }

  /// Called from the verify-email screen after the user confirms.
  Future<void> refreshAfterVerification() async {
    emit(const AuthLoading());
    final profile = await _repo.getProfile();
    if (profile != null && profile.isAllowed && !profile.isAdmin) {
      emit(AuthAuthenticated(profile));
    } else {
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> continueAsVisitor() async {
    emit(const AuthLoading());
    try {
      final deviceId = await DeviceUtils.getDeviceId();
      final sessionId = await SessionService.createVisitorSession(deviceId);
      if (sessionId == null) {
        emit(const AuthError(
            'Failed to start visitor session. Please try again.'));
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('visitor_session_id', sessionId);

      final model = await _buildVisitorModel(sessionId, deviceId);
      emit(AuthVisitor(model));
    } catch (e) {
      emit(const AuthError('Something went wrong. Please try again.'));
      debugPrint('Visitor session error: $e');
    }
  }

  /// Rebuilds [AuthVisitor] from a stored `visitor_session_id` on launch.
  Future<bool> restoreVisitorSession() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString('visitor_session_id');
    if (sessionId == null) return false;

    final valid = await SessionService.isVisitorSessionValid(sessionId);
    if (!valid) {
      await prefs.remove('visitor_session_id');
      return false;
    }
    final deviceId = await DeviceUtils.getDeviceId();
    emit(AuthVisitor(await _buildVisitorModel(sessionId, deviceId)));
    return true;
  }

  Future<VisitorSessionModel> _buildVisitorModel(
      String sessionId, String deviceId) async {
    final minutes =
        await SessionService.getVisitorRemainingMinutes(sessionId);
    final now = DateTime.now();
    return VisitorSessionModel(
      id: sessionId,
      deviceId: deviceId,
      startedAt: now,
      expiresAt: now.add(Duration(minutes: minutes)),
    );
  }

  /// Checks whether the current visitor session is still within its 2h window.
  bool get isVisitorSessionValid {
    final s = state;
    return s is AuthVisitor && s.session.isStillValid;
  }

  Future<void> signOut() async {
    await _repo.signOut();
    emit(const AuthUnauthenticated());
  }
}
