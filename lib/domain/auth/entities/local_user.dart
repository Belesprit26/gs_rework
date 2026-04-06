import 'package:equatable/equatable.dart';

class LocalUser extends Equatable {
  const LocalUser({
    required this.uid,
    required this.email,
    required this.fullName,
    this.profilePic,
    this.bio,
  });

  const LocalUser.empty()
      : this(
          uid: '',
          email: '',
          fullName: '',
          profilePic: '',
          bio: '',
        );

  final String uid;
  final String email;
  final String? profilePic;
  final String? bio;
  final String fullName;

  @override
  List<Object?> get props => [
        uid,
        email,
        profilePic,
        bio,
        fullName,
      ];
}
