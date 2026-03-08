import '../../../core/result/result.dart';
import '../entities/local_user.dart';
import '../repositories/auth_repository.dart';

class SignInWithEmailPassword {
  const SignInWithEmailPassword(this._repo);
  final AuthRepository _repo;

  Future<Result<LocalUser>> call({
    required String email,
    required String password,
  }) {
    return _repo.signInWithEmailPassword(email: email, password: password);
  }
}
