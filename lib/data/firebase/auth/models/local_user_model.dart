import '../../../../core/utils/typedefs.dart';
import '../../../../domain/auth/entities/local_user.dart';

class LocalUserModel extends LocalUser {
  const LocalUserModel({
    required super.uid,
    required super.email,
    required super.fullName,
    super.profilePic,
    super.bio,
  });

  const LocalUserModel.empty()
      : this(
          uid: '',
          email: '',
          fullName: '',
        );

  LocalUserModel.fromMap(DataMap map)
      : super(
          uid: map['uid'] as String? ?? '',
          email: map['email'] as String? ?? '',
          fullName: map['fullName'] as String? ?? '',
          profilePic: map['profilePic'] as String?,
          bio: map['bio'] as String?,
        );

  DataMap toMap() {
    return {
      'uid': uid,
      'email': email,
      'profilePic': profilePic,
      'bio': bio,
      'fullName': fullName,
    };
  }
}
