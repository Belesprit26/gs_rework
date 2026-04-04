import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/firebase_auth_error_mapper.dart';
import '../../../core/result/result.dart';
import '../../../core/utils/constants.dart';
import '../../../domain/auth/entities/auth_user.dart';
import '../../../domain/auth/entities/local_user.dart';
import '../../../domain/auth/repositories/auth_repository.dart';
import 'models/local_user_model.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  })  : _auth = auth,
        _firestore = firestore;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  // ── Auth state ────────────────────────────────────────────────────

  @override
  Stream<AuthUser?> authStateChanges() {
    return _auth.authStateChanges().map(_mapAuthUser);
  }

  @override
  AuthUser? currentUser() => _mapAuthUser(_auth.currentUser);

  // ── Sign in ───────────────────────────────────────────────────────

  @override
  Future<Result<LocalUser>> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final normalizedEmail = _normalizeEmail(email);
      final cred = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        return const Err(UnexpectedFailure('No user returned from sign in.'));
      }

      final userSnap = await _getUserData(user.uid);
      if (!userSnap.exists) {
        await _setUserData(
          user,
          fallbackEmail: normalizedEmail,
          fullName: user.displayName ?? '',
          profilePic: user.photoURL ?? kDefaultAvatar,
        );
      }

      final refreshed = await _getUserData(user.uid);
      final data = refreshed.data();
      if (data == null) {
        return const Err(UnexpectedFailure('User profile missing after sign in.'));
      }

      return Ok(LocalUserModel.fromMap(data));
    } on FirebaseAuthException catch (e) {
      return Err(ValidationFailure(mapFirebaseAuthCode(e.code)));
    } catch (e) {
      return Err(UnexpectedFailure('Sign in failed: $e'));
    }
  }

  // ── Sign up ───────────────────────────────────────────────────────

  @override
  Future<Result<LocalUser>> signUpWithEmailPassword({
    required String email,
    required String fullName,
    required String password,
  }) async {
    try {
      final normalizedEmail = _normalizeEmail(email);
      final cred = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        return const Err(UnexpectedFailure('No user returned from sign up.'));
      }

      await user.updateDisplayName(fullName);
      await user.updatePhotoURL(kDefaultAvatar);

      await _setUserData(
        user,
        fallbackEmail: normalizedEmail,
        fullName: fullName,
        profilePic: kDefaultAvatar,
      );

      final refreshed = await _getUserData(user.uid);
      final data = refreshed.data();
      if (data == null) {
        return const Err(UnexpectedFailure('User profile missing after sign up.'));
      }

      return Ok(LocalUserModel.fromMap(data));
    } on FirebaseAuthException catch (e) {
      return Err(ValidationFailure(mapFirebaseAuthCode(e.code)));
    } catch (e) {
      return Err(UnexpectedFailure('Sign up failed: $e'));
    }
  }

  // ── Forgot password ───────────────────────────────────────────────

  @override
  Future<Result<void>> forgotPassword({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: _normalizeEmail(email));
      return const Ok(null);
    } on FirebaseAuthException catch (e) {
      return Err(ValidationFailure(mapFirebaseAuthCode(e.code)));
    } catch (e) {
      return Err(UnexpectedFailure('Password reset failed: $e'));
    }
  }

  // ── Sign out ──────────────────────────────────────────────────────

  @override
  Future<Result<void>> signOut() async {
    try {
      await _auth.signOut();
      return const Ok(null);
    } catch (e) {
      return Err(UnexpectedFailure('Sign out failed: $e'));
    }
  }

  // ── Profile completeness ──────────────────────────────────────────

  @override
  Future<bool> isProfileComplete(String uid) async {
    try {
      final snap = await _getUserData(uid);
      final data = snap.data();
      if (data == null) return false;

      final fullName = data['fullName'] as String? ?? '';
      final email = data['email'] as String? ?? '';
      return fullName.isNotEmpty && email.isNotEmpty;
    } catch (_) {
      // If we can't check, assume complete to not block the user.
      return true;
    }
  }

  // ── Private helpers ───────────────────────────────────────────────

  AuthUser? _mapAuthUser(User? user) {
    final email = user?.email;
    if (user == null || email == null) return null;
    return AuthUser(uid: user.uid, email: email);
  }

  String _normalizeEmail(String email) {
    return email.replaceAll(RegExp(r'\s+'), '').trim().toLowerCase();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getUserData(String uid) async {
    return _firestore.collection('users').doc(uid).get();
  }

  Future<void> _setUserData(
    User user, {
    required String fallbackEmail,
    required String fullName,
    required String profilePic,
  }) async {
    final model = LocalUserModel(
      uid: user.uid,
      email: user.email ?? fallbackEmail,
      fullName: fullName,
      profilePic: profilePic,
      temperature: 0.0,
    );

    await _firestore.collection('users').doc(user.uid).set(
          model.toMap(),
          SetOptions(merge: true),
        );
  }

}
