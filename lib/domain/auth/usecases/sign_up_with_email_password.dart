import '../../../core/result/result.dart';
import '../entities/local_user.dart';
import '../repositories/auth_repository.dart';

class SignUpWithEmailPassword {
  const SignUpWithEmailPassword(this._repo);
  final AuthRepository _repo;

  Future<Result<LocalUser>> call({
    required String email,
    required String fullName,
    required String password,
  }) {
    return _repo.signUpWithEmailPassword(
      email: email,
      fullName: fullName,
      password: password,
    );
  }
}
