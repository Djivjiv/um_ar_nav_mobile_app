import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/email_role_config.dart';
import '../../core/config/google_auth_config.dart';
import '../../core/utils/session_service.dart';
import '../local/offline_cache.dart';
import '../models/user_profile_model.dart';
import 'repository_exception.dart';

/// Outcome of the Google Sign-In flow.
enum GoogleSignInStatus { success, cancelled, wrongDomain, networkError, failed }

class GoogleSignInResult {
  final GoogleSignInStatus status;
  final UserProfileModel? profile;

  /// Raw error text (message + runtime type) for diagnostics. Null on success.
  final String? detail;

  const GoogleSignInResult(
    this.status, {
    this.profile,
    this.detail,
  });
}

class AuthRepository {
  final SupabaseClient _client;
  AuthRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

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

  // ───────────────────────── Google Sign-In ─────────────────────────

  Future<GoogleSignInResult> signInWithGoogle() async {
    GoogleSignInAccount? googleUser;
    try {
      debugPrint('[GoogleSignIn] step 1: calling googleSignIn.signIn()');
      // Reuse an already-selected account if there is one, else prompt.
      googleUser = await _googleSignIn.signIn();
      debugPrint('[GoogleSignIn] step 2: account '
          '${googleUser == null ? "null (cancelled)" : "chosen"}');
    } on PlatformException catch (e, st) {
      debugPrint('[GoogleSignIn] signIn() PlatformException: '
          'code=${e.code} message=${e.message}');
      debugPrint('$st');
      if (e.code == GoogleSignIn.kSignInCanceledError) {
        return const GoogleSignInResult(GoogleSignInStatus.cancelled);
      }
      if (e.code == GoogleSignIn.kNetworkError) {
        return GoogleSignInResult(GoogleSignInStatus.networkError,
            detail: '${e.code}: ${e.message}');
      }
      return GoogleSignInResult(GoogleSignInStatus.failed,
          detail: 'PlatformException(${e.code}): ${e.message}');
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
      debugPrint('[GoogleSignIn] rejected wrong domain');
      await _googleSignIn.signOut();
      return const GoogleSignInResult(GoogleSignInStatus.wrongDomain);
    }

    try {
      final googleAuth = await googleUser.authentication;
      debugPrint('[GoogleSignIn] step 3: tokens received');
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
          '${response.user != null ? "present" : "null"} session='
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

    if (existing != null) {
      await _touchLastSeen(user.id);
      return _withStudentRole(UserProfileModel.fromMap(existing));
    }

    final first = firstGoogleProfile(
      id: user.id,
      email: user.email,
      fullName: name,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await _client.from('user_profiles').insert({
        ...first.toInsert(),
        'created_at': now,
        'last_seen': now,
      });
    } catch (_) {
      // A DB trigger may already have created the row, without the role.
      final row = await _client
          .from('user_profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (row != null) return _withStudentRole(UserProfileModel.fromMap(row));
    }
    return first;
  }

  /// The profile a first Google sign-in starts with: an email in the student
  /// format is a verified student; any other asks for a role and is pending
  /// until an admin approves it. db/user_roles.sql enforces the same.
  static UserProfileModel firstGoogleProfile({
    required String id,
    required String? email,
    String? fullName,
  }) {
    final isStudent =
        EmailRoleConfig.classify(email) == SchoolEmailKind.student;
    return UserProfileModel(
      id: id,
      email: email,
      fullName: fullName,
      role: isStudent ? 'student' : null,
      isVerified: isStudent,
    );
  }

  /// A row with no role yet, for an email in the student format, gets the
  /// student role without asking.
  Future<UserProfileModel> _withStudentRole(UserProfileModel profile) async {
    final isStudent =
        EmailRoleConfig.classify(profile.email) == SchoolEmailKind.student;
    if (profile.access != AccountAccess.needsRole || !isStudent) return profile;
    try {
      return await updateRole('student') ?? profile;
    } on RepositoryException catch (e) {
      debugPrint('[GoogleSignIn] student role not saved: ${e.message}');
      return profile;
    }
  }

  Future<UserProfileModel?> updateRole(String role) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      await _client.from('user_profiles').update({
        'role': role,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', user.id);
    } on PostgrestException catch (e) {
      throw RepositoryException('Could not save your role: ${e.message}');
    }
    return getProfile();
  }

  // ───────────────────────── 8-hour session window ─────────────────────────

  Future<bool> hasValidTimedSession() async {
    final user = _client.auth.currentUser;
    if (user == null || _client.auth.currentSession == null) return false;
    return SessionService.isUserSessionValid(user.id);
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(SessionService.loginTimeKey);
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
      // Offline, the last saved copy of this user's profile is used, so an
      // offline launch keeps a valid session instead of signing out.
      final row = await OfflineCache.instance.fetch<Map<String, dynamic>?>(
        'user_profile:${user.id}',
        () async => await _client
            .from('user_profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle(),
      );
      if (row == null) return null;
      return UserProfileModel.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  Future<void> _touchLastSeen(String userId) async {
    try {
      await _client.from('user_profiles').update({
        'last_seen': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);
    } catch (_) {}
  }
}
