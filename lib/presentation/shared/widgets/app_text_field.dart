import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A reusable text field with optional label, inline error, and
/// built-in password-visibility toggle when [obscureText] is true.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.label,
    this.hintText,
    this.errorText,
    this.obscureText = false,
    this.fieldHeight = 60,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onChanged,
    this.suffixIcon,
    this.controller,
    this.maxLength,
    this.inputFormatters,
  });

  final String? label;
  final String? hintText;
  final String? errorText;
  final bool obscureText;
  final double fieldHeight;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;
  final TextEditingController? controller;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  void didUpdateWidget(covariant AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscureText != widget.obscureText) {
      _obscured = widget.obscureText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    // If the caller passed a custom suffixIcon use it, otherwise
    // auto-generate a visibility toggle for password fields.
    Widget? trailing = widget.suffixIcon;
    if (trailing == null && widget.obscureText) {
      trailing = GestureDetector(
        onTap: () => setState(() => _obscured = !_obscured),
        child: Icon(
          _obscured ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          color: Colors.grey,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox.shrink(),
        ],
        SizedBox(
          height: widget.fieldHeight,
          child: TextField(
            controller: widget.controller,
            textAlignVertical: TextAlignVertical.center,
            obscureText: _obscured,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            autofillHints: widget.autofillHints,
            onChanged: widget.onChanged,
            maxLength: widget.maxLength,
            inputFormatters: widget.inputFormatters,
            decoration: InputDecoration(
              hintText: widget.hintText,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              suffixIcon: trailing,
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: hasError
                    ? BorderSide(color: Theme.of(context).colorScheme.error)
                    : BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: hasError
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 4),
          Text(
            widget.errorText!,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}
