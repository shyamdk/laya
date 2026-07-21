import 'package:supabase_flutter/supabase_flutter.dart';

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

bool isValidEmail(String s) => _emailRe.hasMatch(s.trim());

/// Supabase's own error messages are accurate but not written for a
/// Grade-8 student to read. Translate the common ones.
String friendlyAuthError(Object e) {
  final raw = e is AuthException ? e.message : e.toString();
  final m = raw.toLowerCase();

  if (m.contains('invalid login credentials')) return 'Wrong email or password.';
  if (m.contains('already registered') || m.contains('user already exists')) {
    return 'An account with this email already exists — try signing in instead.';
  }
  if (m.contains('unable to validate email')) return 'Enter a valid email address.';
  if (m.contains('password should be at least') || m.contains('password is too short')) {
    return 'Password must be at least 6 characters.';
  }
  if (m.contains('email not confirmed')) return 'Please confirm your email before signing in.';
  if (m.contains('rate limit')) return 'Too many attempts — please wait a moment and try again.';
  if (m.contains('same_password') || m.contains('should be different')) {
    return 'Choose a password different from your current one.';
  }
  return raw;
}
