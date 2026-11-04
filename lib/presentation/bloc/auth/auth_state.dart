part of 'auth_cubit.dart';

sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final UserProfileModel user;
  const AuthAuthenticated(this.user);
}

/// Signed in with Google but has not chosen a role yet. Stays this way while
/// a role is [saving], so the router keeps the user on `/select-role`, and
/// after a failed save, with its [error].
class AuthNeedsRoleSelection extends AuthState {
  final UserProfileModel user;
  final bool saving;
  final String? error;
  const AuthNeedsRoleSelection(this.user, {this.saving = false, this.error});
}

/// Signed in, but the account may not use the app: waiting for an admin,
/// rejected or inactive. See `/account-status`.
class AuthAccountBlocked extends AuthState {
  final AccountAccess access;
  final UserProfileModel user;
  const AuthAccountBlocked(this.access, this.user);
}

class AuthVisitor extends AuthState {
  final VisitorSessionModel session;
  const AuthVisitor(this.session);
}

/// A visitor session ran out: nothing of it is left. See `/visitor-ended`.
class AuthVisitorEnded extends AuthState {
  const AuthVisitorEnded();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}

/// The 2D indoor map (floor plan viewer and the map inside navigation) is for
/// signed-in users. Anyone else gets written directions.
bool canSeeIndoorMap(AuthState state) => state is AuthAuthenticated;
