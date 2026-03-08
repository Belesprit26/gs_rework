import 'package:flutter/material.dart';

class AuthSheet extends StatelessWidget {
  const AuthSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      child: Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.65,
        padding: padding.copyWith(
          bottom: padding.bottom + MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: child,
      ),
    );
  }
}

