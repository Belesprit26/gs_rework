import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/neu/neu.dart';
import '../../theme/app_colors.dart';

/// Soft-UI building blocks for the auth screens, per DESIGN_LANGUAGE.md.
///
/// Deliberately auth-scoped: the shared [AppTextField]/[PrimaryButton]
/// are used by provisioning and other screens the user has signed off
/// as fixed, so restyling them globally is not an option.

// ── Logo badge ─────────────────────────────────────────────────────

/// The brand mark (arc + G asset), optionally on a soft raised plinth.
///
/// The plinth's neu shadows only work over [AppColors.neuBase] — the
/// white highlight needs the mid-tone ground to exist against. On
/// white/`surface` contexts (the app bar), pass [plinth] false and the
/// mark stands alone, exactly as the logo files present it on white:
/// per DESIGN_LANGUAGE.md, depth belongs on the neu ground and stays
/// off flat surfaces.
class AuthLogoBadge extends StatelessWidget {
  const AuthLogoBadge({super.key, this.size = 96, this.plinth = true});

  /// Overall diameter with a plinth; the mark's width without one.
  final double size;

  /// Whether to draw the raised neuBase disc behind the mark.
  final bool plinth;

  @override
  Widget build(BuildContext context) {
    // Proportions tuned at size 96 (mark 65 wide, shadows 7/18).
    final markWidth = plinth ? size * (65 / 96) : size;
    final mark = Image.asset(
      'assets/logos/GS_EC1.png',
      width: markWidth,
      // The mark must never distort; if the asset is missing in a dev
      // build, show nothing rather than a broken-image icon.
      errorBuilder: (_, __, ___) =>
          SizedBox(width: markWidth, height: markWidth * (50 / 58)),
    );

    if (!plinth) return mark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.neuBase,
        shape: BoxShape.circle,
        boxShadow: neuRaisedShadows(
          distance: size * (7 / 96),
          blur: size * (18 / 96),
        ),
      ),
      alignment: Alignment.center,
      child: mark,
    );
  }
}

// ── Mode well ──────────────────────────────────────────────────────

/// Grooved two-lane switch (Sign in / Create account). The ACTIVE lane
/// is carved deeper into the surface with a bold `primary` label —
/// the bottom nav's grooved-active-well grammar.
class AuthModeWell extends StatelessWidget {
  const AuthModeWell({
    super.key,
    required this.labels,
    required this.activeIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int activeIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return NeuInset(
      borderRadius: 18,
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(i),
                child: SizedBox(
                  height: 44,
                  child: i == activeIndex
                      ? NeuInset(
                          borderRadius: 13,
                          padding: EdgeInsets.zero,
                          child: Center(child: _label(labels[i], active: true)),
                        )
                      : Center(child: _label(labels[i], active: false)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String text, {required bool active}) {
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      style: TextStyle(
        fontSize: 14,
        fontWeight: active ? FontWeight.w700 : FontWeight.w600,
        color: active ? AppColors.primary : AppColors.muted,
      ),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

// ── Input well ─────────────────────────────────────────────────────

/// A text field carved into the surface. Focus = 1.5px `primary` ring
/// + teal caret; error = `critical` ring with the message below the
/// well (never inside it — the typed value stays visible).
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.hintText,
    this.icon,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onChanged,
    this.inputFormatters,
  });

  final String hintText;
  final IconData? icon;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  final _focusNode = FocusNode();
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final focused = _focusNode.hasFocus;

    final ringColor = hasError
        ? AppColors.critical
        : focused
            ? AppColors.primary
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: ringColor == null
                ? null
                : Border.all(color: ringColor, width: 1.5),
          ),
          child: NeuInset(
            borderRadius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      size: 19,
                      color: focused ? AppColors.primary : AppColors.muted,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: TextField(
                      focusNode: _focusNode,
                      obscureText: _obscured,
                      keyboardType: widget.keyboardType,
                      textInputAction: widget.textInputAction,
                      autofillHints: widget.autofillHints,
                      onChanged: widget.onChanged,
                      inputFormatters: widget.inputFormatters,
                      cursorColor: AppColors.primary,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.ink,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: widget.hintText,
                        hintStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ),
                  if (widget.obscureText)
                    GestureDetector(
                      onTap: () => setState(() => _obscured = !_obscured),
                      child: Icon(
                        _obscured
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 20,
                        color: AppColors.muted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              widget.errorText!,
              style: const TextStyle(fontSize: 12, color: AppColors.critical),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Primary action ─────────────────────────────────────────────────

/// The one raised element on the screen: full-width teal pill with the
/// focal card's faint "energized" glow. Presses INTO the surface.
class AuthCta extends StatefulWidget {
  const AuthCta({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  State<AuthCta> createState() => _AuthCtaState();
}

class _AuthCtaState extends State<AuthCta> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed!();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        height: 54,
        decoration: BoxDecoration(
          color: _pressed ? const Color(0xFF27807C) : AppColors.primary,
          borderRadius: BorderRadius.circular(27),
          boxShadow: _pressed
              ? const []
              : [
                  ...neuRaisedShadows(distance: 6, blur: 16),
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.30),
                    offset: const Offset(0, 10),
                    blurRadius: 24,
                  ),
                ],
        ),
        alignment: Alignment.center,
        child: widget.isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}
