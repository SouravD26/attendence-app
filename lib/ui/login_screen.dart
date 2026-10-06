import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../state/app_state.dart';

// Palette, kept local so the screen does not shift with the app theme.
const _canvas = Color(0xFF08090A);
const _fieldFill = Color(0xFF101113);
const _hairline = Color(0x14FFFFFF);
const _accent = Color(0xFF5E6AD2); // Linear's indigo
const _text = Color(0xFFF7F8F8);
const _label = Color(0xFFB4B8BF);
const _muted = Color(0xFF8A8F98);
const _faint = Color(0xFF5C616B);

/// Sign-in, styled after Linear: a near-black canvas with one soft accent
/// glow, tight left-aligned type, labels sitting above their fields, hairline
/// borders and small radii.
///
/// This screen carries its own dark palette rather than following the app
/// theme. It is the one surface shown before the user has any context, and a
/// fixed canvas keeps the brand moment identical on every device.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state});

  final AppState state;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final ok = await widget.state.login(
      _idController.text,
      _passwordController.text,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.state.error ?? 'Sign in failed.'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final signingIn = widget.state.auth == AuthStatus.signingIn;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The canvas is dark whatever the system theme is doing.
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _canvas,
      ),
      child: Scaffold(
        backgroundColor: _canvas,
        body: Stack(
          children: [
            const _Glow(),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 32,
                  ),
                  child: ConstrainedBox(
                    // Fill the viewport so the form centres, but never ask for
                    // a negative height: with the keyboard up the available
                    // height can drop below the vertical padding.
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight.isFinite
                          ? math.max(0.0, constraints.maxHeight - 64)
                          : 0.0,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const _Mark(),
                              const SizedBox(height: 32),

                              const Text(
                                'Sign in to Sanmarg',
                                style: TextStyle(
                                  color: _text,
                                  fontSize: 27,
                                  fontWeight: FontWeight.w600,
                                  height: 1.15,
                                  // Tight tracking is most of the look.
                                  letterSpacing: -0.7,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Mark attendance, raise tickets and request '
                                'leave.',
                                style: TextStyle(
                                  color: _muted,
                                  fontSize: 14.5,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 34),

                              _Field(
                                label: 'Employee ID',
                                hint: 'Phone, employee code or email',
                                controller: _idController,
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) =>
                                    _passwordFocus.requestFocus(),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Employee ID is required'
                                        : null,
                              ),
                              const SizedBox(height: 18),

                              _Field(
                                label: 'Password',
                                hint: '••••••••',
                                controller: _passwordController,
                                focusNode: _passwordFocus,
                                obscure: _obscure,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _submit(),
                                // A word reads faster than an eye glyph.
                                trailing: _TextAction(
                                  label: _obscure ? 'Show' : 'Hide',
                                  onTap: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'Password is required'
                                    : null,
                              ),
                              const SizedBox(height: 28),

                              _PrimaryButton(
                                label: 'Sign in',
                                busy: signingIn,
                                onPressed: signingIn ? null : _submit,
                              ),
                              const SizedBox(height: 28),

                              const Text(
                                'Sanmarg HRMS',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF4A4F57),
                                  fontSize: 12,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One soft accent glow behind the top of the form. Nothing else on the canvas
/// competes with it, which is what keeps the screen calm.
class _Glow extends StatelessWidget {
  const _Glow();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.75),
              radius: 0.9,
              colors: [
                _accent.withValues(alpha: 0.16),
                _accent.withValues(alpha: 0.04),
                Colors.transparent,
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

/// The product mark: a small rounded tile, not a large hero icon.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7B86E8), _accent],
          ),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(
          Icons.fingerprint_rounded,
          color: Colors.white,
          size: 23,
        ),
      ),
    );
  }
}

/// Label above, field below — easier to scan than a floating label, and the
/// label stays readable while typing.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    required this.validator,
    this.focusNode,
    this.obscure = false,
    this.textInputAction,
    this.onSubmitted,
    this.trailing,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final String? Function(String?) validator;
  final FocusNode? focusNode;
  final bool obscure;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder line(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c, width: w),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _label,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          textInputAction: textInputAction,
          onFieldSubmitted: onSubmitted,
          validator: validator,
          style: const TextStyle(color: _text, fontSize: 14.5),
          cursorColor: _accent,
          cursorWidth: 1.6,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: _faint, fontSize: 14.5),
            filled: true,
            fillColor: _fieldFill,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 15,
            ),
            suffixIcon: trailing,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            border: line(_hairline),
            enabledBorder: line(_hairline),
            focusedBorder: line(_accent, 1.4),
            errorBorder: line(AppTheme.danger),
            focusedErrorBorder: line(AppTheme.danger, 1.4),
            errorStyle: const TextStyle(fontSize: 12, height: 1.3),
          ),
        ),
      ],
    );
  }
}

/// A quiet text button that sits inside a field.
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: _muted,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Solid, modest radius, no elevation — the one emphatic element on screen.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          disabledBackgroundColor: const Color(0xFF2A2E3D),
          foregroundColor: Colors.white,
          disabledForegroundColor: _muted,
          elevation: 0,
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}
