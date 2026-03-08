import '../../../core/result/result.dart';
import '../entities/auth_user.dart';
import '../entities/local_user.dart';

abstract class AuthRepository {
  Stream<AuthUser?> authStateChanges();
  AuthUser? currentUser();

  Future<Result<LocalUser>> signInWithEmailPassword({
    required String email,
    required String password,
  });

  Future<Result<LocalUser>> signUpWithEmailPassword({
    required String email,
    required String fullName,
    required String password,
  });

  Future<Result<void>> forgotPassword({required String email});

  Future<Result<void>> signOut();

  /// Checks whether the user's Firestore profile is complete enough
  /// to pass the auth gate. Returns true if complete or on error
  /// (to avoid blocking the user).
  Future<bool> isProfileComplete(String uid);
}
