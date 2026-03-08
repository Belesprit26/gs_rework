import '../../../core/result/result.dart';
import '../repositories/auth_repository.dart';

class ForgotPassword {
  const ForgotPassword(this._repo);
  final AuthRepository _repo;

  Future<Result<void>> call({required String email}) {
    return _repo.forgotPassword(email: email);
  }
}
