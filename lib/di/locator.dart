import 'package:get_it/get_it.dart';

import 'register_data.dart';
import 'register_domain.dart';
import 'register_presentation.dart';

final GetIt getIt = GetIt.instance;

Future<void> setupLocator() async {
  // Data first – repositories and Firebase clients
  await registerData(getIt);

  // Domain – use cases and policies (depend on repositories)
  registerDomain(getIt);

  // Presentation – BLoCs and Cubits (depend on use cases)
  registerPresentation(getIt);
}
