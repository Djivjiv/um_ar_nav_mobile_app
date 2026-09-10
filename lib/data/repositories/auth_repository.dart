import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/google_auth_config.dart';
import '../../core/config/supabase_config.dart';
import '../../core/utils/session_service.dart';
import '../models/user_profile_model.dart';
import 'repository_exception.dart';

class AuthResult {
  final UserProfileModel? profile;
  final VisitorSessionModel? visitor;
  final bool needsEmailVerification;

  const AuthResult({
    this.profile,
    this.visitor,
    this.needsEmailVerification = false,
  });
}

/// Outcome of the Google Sign-In flow.
enum GoogleSignInStatus { success, cancelled, wrongDomain, networkError, failed }

class GoogleSignInResult {
  final GoogleSignInStatus status;
  final UserProfileModel? profile;

  /// True when the signed-in user still needs to pick a role.
  final bool needsRoleSelection;

  /// Raw error text (message + runtime type) for diagnostics. Null on success.
  final String? detail;

  const GoogleSignInResult(
    this.status, {
    this.profile,
    this.needsRoleSelection = false,
    this.detail,
  });
}

class AuthRepository {
  final SupabaseClient _client;
  AuthRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  static const _deviceIdKey = 'um_device_id';
  static const _loginTimeKey = 'login_time';

  /// Authenticated sessions are considered valid for this long before the
  /// user must sign in with Google again.
  static const Duration sessionMaxAge = Duration(hours: 8);

  User? getCurrentUser() => _client.auth.currentUser;

  Session? get currentSession => _client.auth.currentSession;

  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: GoogleAuthConfig.scopes,
    // On Android the client is matched by package name + SHA-1, so no
    // clientId is passed. iOS needs its own OAuth client id.
    clientId: (!kIsWeb && Platform.isIOS && GoogleAuthConfig.iosClientId.isNotEmpty)
        ? GoogleAuthConfig.iosClientId
        : null,
    // Supabase validates the id token against the web ("server") client.
    serverClientId: GoogleAuthConfig.webClientId,
    hostedDomain: GoogleAuthConfig.allowedDomain,
  );

  bool isEmailVerified() {
    final user = _client.auth.currentUser;
    return user?.emailConfirmedAt != null;
  }

  bool isSchoolEmail(String email) =>
      email.trim().toLowerCase().endsWith(SupabaseConfig.schoolEmailDomain);

  // ───────────────────────── Sign in ─────────────────────────

  Future<AuthResult> signInWithEmail(String email, String password) async {
    if (!isSchoolEmail(email)) {
      throw RepositoryException(
          'Only ${SupabaseConfig.schoolEmailDomain} emails are allowed');
    }
    try {
      final res = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = res.user;
      if (user == null) {
        throw RepositoryException('Sign in failed. Please try again.');
      }
      if (user.emailConfirmedAt == null) {
        return const AuthResult(needsEmailVerification: true);
      }

      final profile = await _fetchOrCreateProfile(user, email: email);
      if (profile.isAdmin || !profile.isAllowed) {
        await _client.auth.signOut();
        throw RepositoryException(
            'This app is for students and faculty only.');
      }
      await _touchLastSeen(user.id);
      return AuthResult(profile: profile);
    } on AuthException catch (e) {
      throw RepositoryException(e.message);
    }
  }

  // ───────────────────────── Register ─────────────────────────

  Future<AuthResult> registerWithEmail(
    String email,
    String password,
    String fullName,
  ) async {
    if (!isSchoolEmail(email)) {
      throw RepositoryException(
          'Only ${SupabaseConfig.schoolEmailDomain} emails are allowed');
    }
    try {
      final res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': fullName.trim()},
      );
      final user = res.user;
      if (user == null) {
        throw RepositoryException('Registration failed. Please try again.');
      }

      // Best-effort profile row creation (RLS permitting).
      try {
        await _client.from('user_profiles').upsert({
          'id': user.id,
          'email': email.trim(),
          'full_name': fullName.trim(),
          'role': 'student',
          'is_verified': false,
          'is_active': true,
        });
      } catch (_) {/* trigger may already handle this */}

      return const AuthResult(needsEmailVerification: true);
    } on AuthException catch (e) {
      throw RepositoryException(e.message);
    }
  }

  Future<void> resendVerification(String email) async {
    try {
      await _client.auth.resend(type: OtpType.signup, email: email.trim());
    } on AuthException catch (e) {
      throw RepositoryException(e.message);
    }
  }

  // ───────────────────────── Google Sign-In ─────────────────────────

  Future<GoogleSignInResult> signInWithGoogle() async {
    GoogleSignInAccount? googleUser;
    try {
      debugPrint('[GoogleSignIn] step 1: calling googleSignIn.signIn() '
          '(serverClientId=${GoogleAuthConfig.webClientId})');
      // Reuse an already-selected account if there is one, else prompt.
      googleUser = await _googleSignIn.signIn();
      debugPrint('[GoogleSignIn] step 2: googleUser = '
          '${googleUser?.email ?? "null (cancelled)"}');
    } on PlatformException catch (e, st) {
      debugPrint('[GoogleSignIn] signIn() PlatformException: '
          'code=${e.code} message=${e.message} details=${e.details}');
      debugPrint('$st');
      if (e.code == GoogleSignIn.kSignInCanceledError) {
        return const GoogleSignInResult(GoogleSignInStatus.cancelled);
      }
      if (e.code == GoogleSignIn.kNetworkError) {
        return GoogleSignInResult(GoogleSignInStatus.networkError,
            detail: '${e.code}: ${e.message}');
      }
      return GoogleSignInResult(GoogleSignInStatus.failed,
          detail: 'PlatformException(${e.code}): ${e.message}'
              '${e.details != null ? " | ${e.details}" : ""}');
    } catch (e, st) {
      debugPrint('[GoogleSignIn] signIn() error: $e (${e.runtimeType})');
      debugPrint('$st');
      return GoogleSignInResult(GoogleSignInStatus.failed,
          detail: '${e.runtimeType}: $e');
    }

    if (googleUser == null) {
      return const GoogleSignInResult(GoogleSignInStatus.cancelled);
    }

    // Domain check BEFORE authenticating with Supabase.
    final email = googleUser.email.trim().toLowerCase();
    if (!email.endsWith('@${GoogleAuthConfig.allowedDomain}')) {
      debugPrint('[GoogleSignIn] rejected wrong domain: $email');
      await _googleSignIn.signOut();
      return const GoogleSignInResult(GoogleSignInStatus.wrongDomain);
    }

    try {
      final googleAuth = await googleUser.authentication;
      debugPrint('[GoogleSignIn] step 3: tokens received '
          'idToken=${googleAuth.idToken != null ? "present(${googleAuth.idToken!.length} chars)" : "NULL"} '
          'accessToken=${googleAuth.accessToken != null ? "present" : "NULL"}');
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        await _googleSignIn.signOut();
        return const GoogleSignInResult(GoogleSignInStatus.failed,
            detail: 'Google returned a null idToken. This usually means the '
                'serverClientId / Web OAuth client id is wrong or missing.');
      }

      debugPrint('[GoogleSignIn] step 4: calling supabase.signInWithIdToken');
      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );
      debugPrint('[GoogleSignIn] step 5: supabase response user='
          '${response.user?.id ?? "null"} session='
          '${response.session != null ? "present" : "null"}');

      final user = response.user;
      if (user == null) {
        return const GoogleSignInResult(GoogleSignInStatus.failed,
            detail: 'Supabase signInWithIdToken returned no user.');
      }

      final profile = await _handleGoogleProfile(user);
      // Server-timestamped 8-hour session window.
      await SessionService.saveUserSessionStart(user.id);
      debugPrint('[GoogleSignIn] step 6: profile ready, role='
          '${profile.role ?? "<none>"}');
      return GoogleSignInResult(
        GoogleSignInStatus.success,
        profile: profile,
        needsRoleSelection: !profile.hasRole,
      );
    } on AuthException catch (e, st) {
      debugPrint('[GoogleSignIn] Supabase AuthException: '
          '${e.message} (statusCode=${e.statusCode})');
      debugPrint('$st');
      await _googleSignIn.signOut();
      return GoogleSignInResult(GoogleSignInStatus.failed,
          detail: 'Supabase AuthException: ${e.message}');
    } on PostgrestException catch (e, st) {
      debugPrint('[GoogleSignIn] PostgrestException: '
          '${e.message} (code=${e.code})');
      debugPrint('$st');
      return GoogleSignInResult(GoogleSignInStatus.failed,
          detail: 'Database error (${e.code}): ${e.message}');
    } on PlatformException catch (e, st) {
      debugPrint('[GoogleSignIn] PlatformException after signIn: '
          'code=${e.code} message=${e.message}');
      debugPrint('$st');
      if (e.code == GoogleSignIn.kNetworkError) {
        return GoogleSignInResult(GoogleSignInStatus.networkError,
            detail: '${e.code}: ${e.message}');
      }
      return GoogleSignInResult(GoogleSignInStatus.failed,
          detail: 'PlatformException(${e.code}): ${e.message}');
    } catch (e, st) {
      debugPrint('[GoogleSignIn] FULL ERROR: $e');
      debugPrint('[GoogleSignIn] Error type: ${e.runtimeType}');
      debugPrint('$st');
      return GoogleSignInResult(GoogleSignInStatus.failed,
          detail: '${e.runtimeType}: $e');
    }
  }

  Future<UserProfileModel> _handleGoogleProfile(User user) async {
    final existing = await _client
        .from('user_profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    final name = user.userMetadata?['full_name']?.toString() ??
        user.userMetadata?['name']?.toString() ??
        '';

    if (existing == null) {
      final now = DateTime.now().toIso8601String();
      final payload = {
        'id': user.id,
        'email': user.email,
        'full_name': name,
        'role': null,
        'is_verified': true,
        'is_active': true,
        'created_at': now,
        'last_seen': now,
      };
      try {
        await _client.from('user_profiles').insert(payload);
      } catch (_) {/* a DB trigger may already create the row */}
      return UserProfileModel(
        id: user.id,
        email: user.email,
        fullName: name,
        isVerified: true,
      );
    }

    await _touchLastSeen(user.id);
    return UserProfileModel.fromMap(existing);
  }

  Future<UserProfileModel?> updateRole(String role) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      await _client
          .from('user_profiles')
          .update({'role': role, 'last_seen': DateTime.now().toIso8601String()})
          .eq('id', user.id);
    } on PostgrestException catch (e) {
      throw RepositoryException('Could not save your role: ${e.message}');
    }
    return getProfile();
  }

  // ───────────────────────── 8-hour session window ─────────────────────────

  Future<void> saveLoginTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_loginTimeKey, DateTime.now().toIso8601String());
  }

  Future<bool> hasValidTimedSession() async {
    final user = _client.auth.currentUser;
    if (user == null || _client.auth.currentSession == null) return false;
    return SessionService.isUserSessionValid(user.id);
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_loginTimeKey);
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _client.auth.signOut();
  }

  // ───────────────────────── Profiles ─────────────────────────

  Future<UserProfileModel?> getProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final row = await _client
          .from('user_profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (row == null) return null;
      return UserProfileModel.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  Future<UserProfileModel> _fetchOrCreateProfile(User user,
      {required String email}) async {
    final row = await _client
        .from('user_profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    if (row != null) return UserProfileModel.fromMap(row);

    final fallback = UserProfileModel(
      id: user.id,
      email: email.trim(),
      fullName: user.userMetadata?['full_name']?.toString(),
      role: 'student',
      isVerified: user.emailConfirmedAt != null,
    );
    try {
      await _client.from('user_profiles').upsert(fallback.toInsert());
    } catch (_) {/* RLS may block; still return the model */}
    return fallback;
  }

  Future<void> _touchLastSeen(String userId) async {
    try {
      await _client
          .from('user_profiles')
          .update({'last_seen': DateTime.now().toIso8601String()}).eq(
              'id', userId);
    } catch (_) {}
  }

  // ───────────────────────── Visitor ─────────────────────────

  Future<VisitorSessionModel> createVisitorSession() async {
    final deviceId = await _deviceId();
    final now = DateTime.now();
    final expires = now.add(const Duration(hours: 2));
    try {
      final row = await _client
          .from('visitor_sessions')
          .insert({
            'device_id': deviceId,
            'started_at': now.toIso8601String(),
            'expires_at': expires.toIso8601String(),
            'is_expired': false,
          })
          .select()
          .single();
      return VisitorSessionModel.fromMap(row);
    } on PostgrestException catch (e) {
      throw RepositoryException('Could not start a visitor session: ${e.message}');
    } catch (_) {
      // Allow offline visitor browsing with a local-only session.
      return VisitorSessionModel(
        id: 'local-$deviceId',
        deviceId: deviceId,
        startedAt: now,
        expiresAt: expires,
      );
    }
  }

  Future<VisitorSessionModel?> getActiveVisitorSession() async {
    final deviceId = await _deviceId();
    try {
      final row = await _client
          .from('visitor_sessions')
          .select()
          .eq('device_id', deviceId)
          .eq('is_expired', false)
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      final session = VisitorSessionModel.fromMap(row);
      return session.isStillValid ? session : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null) return existing;

    String platform = 'unknown';
    try {
      platform = Platform.operatingSystem;
    } catch (_) {}
    final rand = Random();
    final suffix = List.generate(12, (_) => rand.nextInt(16).toRadixString(16))
        .join();
    final id = '$platform-$suffix';
    await prefs.setString(_deviceIdKey, id);
    return id;
  }
}
