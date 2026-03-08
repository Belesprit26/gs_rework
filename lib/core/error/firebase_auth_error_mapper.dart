/// Maps Firebase Auth error codes to user-friendly messages.
///
/// Reference: https://firebase.google.com/docs/auth/admin/errors
String mapFirebaseAuthCode(String code) {
  return switch (code) {
    'invalid-email' => 'The email address is not valid.',
    'user-disabled' => 'This account has been disabled.',
    'user-not-found' => 'No account found with that email.',
    'wrong-password' => 'Incorrect password. Please try again.',
    'invalid-credential' => 'Invalid credentials. Please check your email and password.',
    'email-already-in-use' => 'An account already exists with that email.',
    'operation-not-allowed' => 'Email/password sign-in is not enabled.',
    'weak-password' => 'Password is too weak. Use at least 6 characters.',
    'too-many-requests' => 'Too many attempts. Please wait a moment and try again.',
    'network-request-failed' => 'Network error. Check your connection and try again.',
    'requires-recent-login' => 'Please sign in again to complete this action.',
    'account-exists-with-different-credential' =>
      'An account already exists with the same email but a different sign-in method.',
    _ => 'Something went wrong. Please try again.',
  };
}
