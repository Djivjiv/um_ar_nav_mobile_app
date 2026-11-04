import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/user_profile_model.dart';
import '../../../data/models/visitor_session_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/repository_exception.dart';
import '../../../data/repositories/visitor_session_repository.dart';

part 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final AuthRepository _repo;
  final VisitorSessionRepository _visitors;

  AuthCubit(this._repo, {VisitorSessionRepository? visitors})
      : _visitors = visitors ?? VisitorSessionRepository(),
        super(const AuthInitial());

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
    await _emitForProfile(profile);
    return true;
  }

  /// The one place a profile becomes a state, so an account can't get in by
  /// any route without passing the same checks. A rejected or inactive
  /// account is signed out; a pending one stays signed in to check again.
  Future<void> _emitForProfile(UserProfileModel profile) async {
    final access = profile.access;
    switch (access) {
      case AccountAccess.allowed:
        emit(AuthAuthenticated(profile));
      case AccountAccess.needsRole:
        emit(AuthNeedsRoleSelection(profile));
      case AccountAccess.pending:
        emit(AuthAccountBlocked(access, profile));
      case AccountAccess.rejected:
      case AccountAccess.inactive:
        try {
          await _repo.signOut();
        } catch (e) {
          debugPrint('Sign-out of a blocked account failed: $e');
        }
        emit(AuthAccountBlocked(access, profile));
    }
  }

  /// Reads the profile again: "Check again" on the pending screen, and each
  /// return to the app, so a decision by an admin takes effect without a new
  /// sign-in. Without a profile (signed out, nothing cached) nothing changes.
  Future<void> recheckAccess() async {
    final current = state;
    if (current is! AuthAuthenticated && current is! AuthAccountBlocked) return;
    final profile = await _repo.getProfile();
    if (profile == null) return;
    if (current is AuthAuthenticated &&
        profile.access == AccountAccess.allowed) {
      return;
    }
    await _emitForProfile(profile);
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
        await _emitForProfile(result.profile!);
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
    if (current is! AuthNeedsRoleSelection || current.saving) return;
    const failed = 'Could not save your role. Please try again.';
    emit(AuthNeedsRoleSelection(current.user, saving: true));
    try {
      final profile = await _repo.updateRole(role);
      if (profile != null && profile.hasRole) {
        await _emitForProfile(profile);
      } else {
        emit(AuthNeedsRoleSelection(current.user, error: failed));
      }
    } on RepositoryException catch (e) {
      emit(AuthNeedsRoleSelection(current.user, error: e.message));
    } catch (e) {
      debugPrint('Role not saved: $e');
      emit(AuthNeedsRoleSelection(current.user, error: failed));
    }
  }

  /// Starts a visitor session, or carries on with the one still running.
  /// Each session of a device has the same `device_code`.
  Future<void> continueAsVisitor() async {
    emit(const AuthLoading());
    try {
      final session = await _visitors.start();
      emit(session == null
          ? const AuthError(
              'Failed to start visitor session. Please try again.')
          : AuthVisitor(session));
    } catch (e) {
      emit(const AuthError('Something went wrong. Please try again.'));
      debugPrint('Visitor session error: $e');
    }
  }

  /// Rebuilds [AuthVisitor] from the saved session on launch. A saved session
  /// that ran out while the app was closed ends the same way as one that runs
  /// out in use.
  Future<bool> restoreVisitorSession() async {
    final session = await _visitors.restore();
    if (session == null) return false;
    if (!session.isStillValid) {
      await endVisitorSession();
      return false;
    }
    emit(AuthVisitor(session));
    return true;
  }

  /// Checks the running visitor session, and ends it when its time is up or
  /// the server has closed it. `VisitorExpiryWatcher` calls this all the time.
  Future<void> checkVisitorSession() async {
    final current = state;
    if (current is! AuthVisitor || _checkingVisitor) return;
    // One at a time: a slow check finishing after another ended the session
    // would save it again.
    _checkingVisitor = true;
    try {
      final session = await _visitors.refresh(current.session);
      if (state is! AuthVisitor) return;
      if (!session.isStillValid) {
        await endVisitorSession();
      } else if (session.expiresAt != current.session.expiresAt) {
        emit(AuthVisitor(session));
      }
    } finally {
      _checkingVisitor = false;
    }
  }

  bool _checkingVisitor = false;

  /// Signs the visitor out and removes everything of the session.
  Future<void> endVisitorSession() async {
    await _visitors.clear();
    emit(const AuthVisitorEnded());
  }

  Future<void> signOut() async {
    await _repo.signOut();
    emit(const AuthUnauthenticated());
  }
}
