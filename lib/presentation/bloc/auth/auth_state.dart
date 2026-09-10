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

/// Signed in with Google but has not chosen a role yet.
class AuthNeedsRoleSelection extends AuthState {
  final UserProfileModel user;
  const AuthNeedsRoleSelection(this.user);
}

class AuthVisitor extends AuthState {
  final VisitorSessionModel session;
  const AuthVisitor(this.session);
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthNeedsVerification extends AuthState {
  final String email;
  const AuthNeedsVerification(this.email);
}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}
