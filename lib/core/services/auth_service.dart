import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_error.dart';
import '../logging/app_logger.dart';
import 'profile_service.dart';
import 'supabase_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

final class AuthService {
  AuthService._();

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
      final newStatus =
          session != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;

      if (newStatus != _currentStatus) {
        _currentStatus = newStatus;
        _authStatusController.add(newStatus);
        AppLogger.info('Auth state changed: ${newStatus.name}');

        if (newStatus == AuthStatus.authenticated) {
          await _loadProfileForSession();
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
    } catch (e) {
      AppLogger.error('Profile load failed after auth: $e');
    }
  }

  static Future<void> signUp({
    required String email,
    required String password,
  }) async {
    try {
      AppLogger.info('Attempting sign up for: $email');
      final response = await _auth.signUp(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw const AuthError(message: 'Sign up failed. Please try again.');
      }

      AppLogger.info('Sign up successful for: $email');
    } on AuthException catch (e) {
      AppLogger.error('Sign up AuthException: ${e.message}');
      throw AuthError(message: _mapAuthErrorMessage(e.message));
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
      AppLogger.info('Attempting sign in for: $email');
      final response = await _auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw const AuthError(message: 'Sign in failed. Please try again.');
      }

      AppLogger.info('Sign in successful for: $email');
    } on AuthException catch (e) {
      AppLogger.error('Sign in AuthException: ${e.message}');
      throw AuthError(message: _mapAuthErrorMessage(e.message));
    } catch (e) {
      if (e is AuthError) rethrow;
      AppLogger.error('Sign in unexpected error: $e');
      throw const AuthError(message: 'An unexpected error occurred. Please try again.');
    }
  }

  static Future<void> signOut() async {
    try {
      AppLogger.info('Signing out...');
      await _auth.signOut();
      AppLogger.info('Sign out successful.');
    } on AuthException catch (e) {
      AppLogger.error('Sign out AuthException: ${e.message}');
      throw AuthError(message: _mapAuthErrorMessage(e.message));
    } catch (e) {
      if (e is AuthError) rethrow;
      AppLogger.error('Sign out unexpected error: $e');
      throw const AuthError(message: 'An unexpected error occurred during sign out.');
    }
  }

  static String _mapAuthErrorMessage(String supabaseMessage) {
    final lower = supabaseMessage.toLowerCase();

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
