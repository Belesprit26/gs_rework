import 'package:flutter/material.dart';

import 'auth_sheet.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.header,
    required this.child,
  });

  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: header),
          Align(
            alignment: Alignment.bottomCenter,
            child: AuthSheet(child: child),
          ),
        ],
      ),
    );
  }
}

