import '../../../core/result/result.dart';
import '../repositories/auth_repository.dart';

class SignOut {
  const SignOut(this._repo);
  final AuthRepository _repo;

  Future<Result<void>> call() {
    return _repo.signOut();
  }
}
