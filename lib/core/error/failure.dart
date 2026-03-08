import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  const Failure();

  String get message;

  @override
  List<Object?> get props => [message];
}

class ValidationFailure extends Failure {
  const ValidationFailure(this.message);

  @override
  final String message;
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure([this.message = 'Unexpected error']);

  @override
  final String message;
}
