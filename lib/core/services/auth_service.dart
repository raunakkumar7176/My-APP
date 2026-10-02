import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import 'profile_service.dart';
import 'push_notification_service.dart';
import 'single_device_enforcer.dart';
import 'supabase_service.dart';

enum AuthStatus {
  unknown,
  authenticated,
  unauthenticated,

  /// A session exists, but it came from a password-reset email link
  /// (`AuthChangeEvent.passwordRecovery`), not a real sign-in — the
  /// previous behavior here only ever checked `session != null`, so this
  /// temporary recovery session was indistinguishable from a normal login
  /// and the router sent the user straight to Home instead of letting
  /// them actually set a new password. Sticky: stays set until
  /// [AuthService.completePasswordRecovery] succeeds (or the user signs
  /// out), so a later TOKEN_REFRESHED/USER_UPDATED event on the same
  /// session can't silently escape the reset screen early.
  passwordRecovery,
}

final class AuthService {
  AuthService._();

  /// Custom Android deep-link scheme the app registers in AndroidManifest.xml
  /// (`<data android:scheme="my-preparation" android:host="auth-callback"/>`).
  /// Passed as `emailRedirectTo` so Supabase's confirmation email points here
  /// instead of falling back to the project's Site URL (which is a localhost
  /// dev URL, never reachable from a device) — this is the actual production
  /// bug: a build with no `emailRedirectTo` inherits the dashboard's Site URL.
  /// Must also be added to Supabase Dashboard → Authentication → URL
  /// Configuration → Redirect URLs, or GoTrue rejects it as "unauthorized".
  /// supabase_flutter already listens for this scheme automatically
  /// (`FlutterAuthClientOptions.detectSessionInUri` defaults to true) — no
  /// extra deep-link handling code is needed here.
  static const String emailVerificationRedirectUrl =
      'my-preparation://auth-callback';

  static final StreamController<AuthStatus> _authStatusController =
      StreamController<AuthStatus>.broadcast();

  static Stream<AuthStatus> get authStatusStream => _authStatusController.stream;

  static AuthStatus _currentStatus = AuthStatus.unknown;
  static AuthStatus get currentStatus => _currentStatus;

  static GoTrueClient get _auth => SupabaseService.client.auth;

  static User? get currentUser => _auth.currentUser;
  static Session? get currentSession => _auth.currentSession;
  static bool get isAuthenticated => currentUser != null;

  static void initialize() {
    _auth.onAuthStateChange.listen((data) async {
      final session = data.session;

      // Must be checked before the normal authenticated/unauthenticated
      // branch below: this event's session is non-null (GoTrue does
      // authenticate the user from the reset link) but it must never be
      // treated as a real login.
      if (data.event == AuthChangeEvent.passwordRecovery) {
        if (_currentStatus != AuthStatus.passwordRecovery) {
          _currentStatus = AuthStatus.passwordRecovery;
          _authStatusController.add(_currentStatus);
          AppLogger.info('AUTH_DEBUG: Password recovery session detected');
        }
        return;
      }
      // Once in recovery mode, ignore every other auth event (a token
      // refresh on the same recovery session, etc.) until
      // completePasswordRecovery() explicitly clears it — otherwise a
      // TOKEN_REFRESHED firing while the reset screen is still open would
      // flip status back to authenticated and bounce the user to Home
      // before they ever set a new password.
      if (_currentStatus == AuthStatus.passwordRecovery) return;

      final newStatus =
          session != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;

      if (newStatus != _currentStatus) {
        _currentStatus = newStatus;
        _authStatusController.add(newStatus);
        AppLogger.info('AUTH_DEBUG: Session state changed -> ${newStatus.name}');

        if (newStatus == AuthStatus.authenticated) {
          await _loadProfileForSession();
          // Best-effort: register this device's FCM token now that a
          // session exists. Never requests permission itself (see
          // PushNotificationService.registerCurrentDevice) — only sends a
          // token if the OS permission was already granted.
          unawaited(PushNotificationService.instance.registerCurrentDevice());
          // Single-device-login: tell the server this device is now the
          // active one — independent of push permission, since enforcement
          // must work even for a user who denied notifications.
          unawaited(SingleDeviceEnforcer.registerThisDevice());
        } else {
          ProfileService.reset();
        }
      }
    });

    final session = _auth.currentSession;
    _currentStatus =
        session != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
    _authStatusController.add(_currentStatus);
    AppLogger.info('Auth initial status: ${_currentStatus.name}');

    if (_currentStatus == AuthStatus.authenticated) {
      _loadProfileForSession();
    }
  }

  static Future<void> _loadProfileForSession() async {
    try {
      await ProfileService.loadProfile();
      unawaited(ProfileService.tryApplyPendingReferral());
    } catch (e) {
      AppLogger.error('Profile load failed after auth: $e');
    }
  }

  static Future<void> signUp({
    required String email,
    required String password,
  }) async {
    try {
      AppLogger.info('AUTH_DEBUG: Sign-up request started');
      final response = await _auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: emailVerificationRedirectUrl,
      );
      AppLogger.info('AUTH_DEBUG: Sign-up result received');

      if (response.user == null) {
        throw const AuthError(message: 'Sign up failed. Please try again.');
      }

      // response.session is non-null only when email confirmation is OFF
      // (or the project auto-confirms) — that case needs no extra handling
      // here: AuthService.initialize()'s onAuthStateChange listener already
      // picks up the new session and flips AuthStatus to authenticated,
      // which the router redirects to /home on its own. When confirmation
      // IS required, session is null and the caller (AuthScreen) already
      // shows "check your email to verify" rather than treating this as a
      // failure — both paths are already correct, this log just makes the
      // branch visible for diagnosis.
      AppLogger.info(
        'AUTH_DEBUG: Sign-up ${response.session != null ? "issued a session (email confirmation not required)" : "created the account; email confirmation pending"}',
      );
    } on AuthException catch (e) {
      AppLogger.error(
        'Sign up AuthException: message=${e.message}, statusCode=${e.statusCode}, code=${e.code}',
      );
      throw AuthError(message: _mapAuthErrorMessage(e.message, code: e.code));
    } catch (e) {
      if (e is AuthError) rethrow;
      AppLogger.error('Sign up unexpected error: $e');
      throw const AuthError(message: 'An unexpected error occurred. Please try again.');
    }
  }

  static Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      AppLogger.info('AUTH_DEBUG: Sign-in request started');
      final response = await _auth.signInWithPassword(
        email: email,
        password: password,
      );
      AppLogger.info('AUTH_DEBUG: Sign-in result received');

      if (response.user == null) {
        throw const AuthError(message: 'Sign in failed. Please try again.');
      }

      AppLogger.info('AUTH_DEBUG: Sign-in successful');
    } on AuthException catch (e) {
      AppLogger.error(
        'Sign in AuthException: message=${e.message}, statusCode=${e.statusCode}, code=${e.code}',
      );
      throw AuthError(message: _mapAuthErrorMessage(e.message, code: e.code));
    } catch (e) {
      if (e is AuthError) rethrow;
      AppLogger.error('Sign in unexpected error: $e');
      throw const AuthError(message: 'An unexpected error occurred. Please try again.');
    }
  }

  static Future<void> signOut() async {
    try {
      AppLogger.info('Signing out...');
      // Must run BEFORE _auth.signOut() clears the session — deactivating
      // this device's token needs the still-authenticated client. Only
      // THIS device's token is touched (Phase 16: other devices signed
      // into the same account keep receiving push).
      await PushNotificationService.instance.deactivateCurrentDevice();
      await _auth.signOut();
      AppLogger.info('Sign out successful.');
    } on AuthException catch (e) {
      AppLogger.error(
        'Sign out AuthException: message=${e.message}, statusCode=${e.statusCode}, code=${e.code}',
      );
      throw AuthError(message: _mapAuthErrorMessage(e.message, code: e.code));
    } catch (e) {
      if (e is AuthError) rethrow;
      AppLogger.error('Sign out unexpected error: $e');
      throw const AuthError(message: 'An unexpected error occurred during sign out.');
    }
  }

  /// Completes a password-recovery session started by the reset-password
  /// email link: sets the new password on the still-authenticated recovery
  /// session, then explicitly clears the sticky [AuthStatus.passwordRecovery]
  /// flag so the router lets the user through to Home. Must be called
  /// instead of relying on the next [onAuthStateChange] event, since a
  /// successful `updateUser` fires `AuthChangeEvent.userUpdated`, which the
  /// listener in [initialize] deliberately ignores while recovery is active.
  static Future<void> completePasswordRecovery({
    required String newPassword,
  }) async {
    try {
      AppLogger.info('AUTH_DEBUG: Completing password recovery');
      await _auth.updateUser(UserAttributes(password: newPassword));

      _currentStatus = AuthStatus.authenticated;
      _authStatusController.add(_currentStatus);
      AppLogger.info('AUTH_DEBUG: Password recovery completed');
    } on AuthException catch (e) {
      AppLogger.error(
        'Password recovery AuthException: message=${e.message}, statusCode=${e.statusCode}, code=${e.code}',
      );
      throw AuthError(message: _mapAuthErrorMessage(e.message, code: e.code));
    } catch (e) {
      if (e is AuthError) rethrow;
      AppLogger.error('Password recovery unexpected error: $e');
      throw const AuthError(
        message: 'An unexpected error occurred. Please try again.',
      );
    }
  }

  static String _mapAuthErrorMessage(String supabaseMessage, {String? code}) {
    final lower = supabaseMessage.toLowerCase();

    // Prefer the machine-readable error code (stable across GoTrue message
    // wording changes) over substring-matching the human-readable message,
    // where Supabase actually gives us one.
    if (code == 'email_not_confirmed') {
      return 'Please verify your email before logging in. Check your inbox for the confirmation link.';
    }

    if (lower.contains('email not confirmed') ||
        lower.contains('email is not confirmed')) {
      return 'Please verify your email before logging in. Check your inbox for the confirmation link.';
    }
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid email or password')) {
      return 'Incorrect email or password. Please try again.';
    }
    if (lower.contains('user already registered') ||
        lower.contains('already been registered')) {
      return 'An account with this email already exists.';
    }
    if (lower.contains('password should be at least') ||
        lower.contains('Password is too short')) {
      return 'Password must be at least 6 characters long.';
    }
    if (lower.contains('invalid email') || lower.contains('not valid')) {
      return 'Please enter a valid email address.';
    }
    if (lower.contains('email rate limit exceeded')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'Network error. Please check your connection and try again.';
    }
    if (lower.contains('session') || lower.contains('expired')) {
      return 'Your session has expired. Please sign in again.';
    }

    AppLogger.warning('Unmapped auth error: $supabaseMessage');
    return 'Authentication failed. Please try again.';
  }

  static void dispose() {
    _authStatusController.close();
  }
}
