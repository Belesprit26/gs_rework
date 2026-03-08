import 'package:equatable/equatable.dart';

class AuthUser extends Equatable {
  const AuthUser({
    required this.uid,
    required this.email,
  });

  final String uid;
  final String email;

  @override
  List<Object?> get props => [uid, email];
}
