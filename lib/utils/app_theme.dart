import 'package:flutter/material.dart';

/// Centralized app theme, colors, gradients, and reusable animated widgets.
class AppTheme {
  // ── Brand Palette ───────────────────────────────────────────────────────────
  static const Color primary       = Color(0xFF1A3C8B);
  static const Color primaryDark   = Color(0xFF0F2A6B);
  static const Color primaryDeep   = Color(0xFF0D1F4A);
  static const Color accent        = Color(0xFF5B4A9F);
  static const Color accentDark    = Color(0xFF4A3280);
  static const Color accentBlue    = Color(0xFF317AF7);
  static const Color accentPurple  = Color(0xFF7C3AED);
  static const Color surface       = Color(0xFF1A1A1A);
  static const Color surfaceDark   = Color(0xFF0F0F0F);
  static const Color card          = Color(0xFF151515);
  static const Color border        = Color(0xFF2A2A2A);
  static const Color danger        = Color(0xFFFF4F92);
  static const Color error         = Color(0xFFDC2626);
  static const Color warning       = Color(0xFFFF9500);
  static const Color success       = Color(0xFF30D158);
  static const Color background    = Color(0xFF0A0A0F);

  // ── Text Colors ─────────────────────────────────────────────────────────────
  static const Color textPrimary   = Colors.white;
  static const Color textSecondary = Colors.white70;
  static const Color textMuted     = Colors.white54;
  static const Color textHint      = Colors.white30;

  // ── Standard Radius ─────────────────────────────────────────────────────────
  static const double radiusS  = 8;
  static const double radiusM  = 12;
  static const double radiusL  = 16;
  static const double radiusXL = 20;

  // ── Gradients ───────────────────────────────────────────────────────────────
  static const Gradient primaryGrad = LinearGradient(
    colors: [Color(0xFF5B4A9F), Color(0xFF4A3280)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient blueGrad = LinearGradient(
    colors: [Color(0xFF1A3C8B), Color(0xFF0F2A6B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient accentBlueGrad = LinearGradient(
    colors: [Color(0xFF317AF7), Color(0xFF1A3C8B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient darkBgGrad = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0A0A0F), Color(0xFF101722), Color(0xFF0A0A0F)],
  );

  static const Gradient cardGrad = LinearGradient(
    colors: [Color(0xFF1A3C8B), Color(0xFF0D1F4A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient surfaceGrad = LinearGradient(
    colors: [Color(0xFF1E1E2A), Color(0xFF151515)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── TextStyles ──────────────────────────────────────────────────────────────
  static const TextStyle headline = TextStyle(
    color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold,
  );
  static const TextStyle subtitle = TextStyle(
    color: Colors.white70, fontSize: 14, height: 1.5,
  );
  static const TextStyle cardTitle = TextStyle(
    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600,
  );
  static const TextStyle label = TextStyle(
    color: Colors.white60, fontSize: 13,
  );

  // ── Input Decoration ────────────────────────────────────────────────────────
  static InputDecoration inputDecoration({
    required String label,
    Widget? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60),
      prefixIcon: prefix,
      suffixIcon: suffix,
      filled: true,
      fillColor: surfaceDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusM),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusM),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusM),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
    );
  }

  // ── Button Style ────────────────────────────────────────────────────────────
  static ButtonStyle primaryButtonStyle({Color? bg}) => ElevatedButton.styleFrom(
    backgroundColor: bg ?? primary,
    padding: const EdgeInsets.symmetric(vertical: 16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusM)),
    elevation: 0,
  );

  // ── Card Decoration ─────────────────────────────────────────────────────────
  static BoxDecoration cardDecoration({
    Color? color,
    Gradient? gradient,
    double radius = radiusL,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: gradient == null ? (color ?? card) : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      border: borderColor != null ? Border.all(color: borderColor) : null,
    );
  }

  // ── SnackBar Helpers ────────────────────────────────────────────────────────
  static SnackBar successSnackBar(String message) => SnackBar(
    content: Row(children: [
      const Icon(Icons.check_circle, color: Colors.white, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(message)),
    ]),
    backgroundColor: success,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusM)),
    duration: const Duration(seconds: 3),
  );

  static SnackBar errorSnackBar(String message) => SnackBar(
    content: Row(children: [
      const Icon(Icons.error_outline, color: Colors.white, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(message)),
    ]),
    backgroundColor: error,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusM)),
    duration: const Duration(seconds: 3),
  );

  // ── Standard AppBar ─────────────────────────────────────────────────────────
  static AppBar standardAppBar({
    required String title,
    List<Widget>? actions,
    Widget? leading,
    required BuildContext context,
  }) {
    return AppBar(
      backgroundColor: surface,
      elevation: 0,
      leading: leading ?? IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      actions: actions,
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Reusable Animated Widgets
// ────────────────────────────────────────────────────────────────────────────

/// Fades + slides a child widget in on mount.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset beginOffset;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 500),
    this.beginOffset = const Offset(0, 0.3),
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: widget.beginOffset, end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}

/// Pulsing glow container for active status indicators.
class PulsingDot extends StatefulWidget {
  final Color color;
  final double size;

  const PulsingDot({super.key, required this.color, this.size = 10});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.7, end: 1.3)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: _scale,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.5),
                blurRadius: 6,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      );
}

/// Bounces scale on tap.
class TapBounce extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const TapBounce({super.key, required this.child, this.onTap});

  @override
  State<TapBounce> createState() => _TapBounceState();
}

class _TapBounceState extends State<TapBounce>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.94)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

/// Staggered list – animates each item in with a delay.
class StaggeredList extends StatelessWidget {
  final List<Widget> children;
  final Duration itemDelay;
  final Duration itemDuration;

  const StaggeredList({
    super.key,
    required this.children,
    this.itemDelay = const Duration(milliseconds: 80),
    this.itemDuration = const Duration(milliseconds: 400),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < children.length; i++)
          FadeSlideIn(
            delay: itemDelay * i,
            duration: itemDuration,
            child: children[i],
          ),
      ],
    );
  }
}

/// Shimmer loading effect.
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 12,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + _animation.value * 2, 0),
              end: Alignment(1.0 + _animation.value * 2, 0),
              colors: const [
                Color(0xFF2A2A2A),
                Color(0xFF3A3A3A),
                Color(0xFF2A2A2A),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Animated gradient background (slowly shifting).
class AnimatedGradientBg extends StatefulWidget {
  final Widget child;

  const AnimatedGradientBg({super.key, required this.child});

  @override
  State<AnimatedGradientBg> createState() => _AnimatedGradientBgState();
}

class _AnimatedGradientBgState extends State<AnimatedGradientBg>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  static const _colorSets = [
    [Color(0xFF0A0A0F), Color(0xFF101722), Color(0xFF0D1020)],
    [Color(0xFF0D1020), Color(0xFF0A0F1A), Color(0xFF0A0A0F)],
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        final t = _controller.value;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(_colorSets[0][0], _colorSets[1][0], t)!,
                Color.lerp(_colorSets[0][1], _colorSets[1][1], t)!,
                Color.lerp(_colorSets[0][2], _colorSets[1][2], t)!,
              ],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Animated counter that counts up to a value.
class AnimatedCounter extends StatefulWidget {
  final double value;
  final String suffix;
  final TextStyle style;
  final Duration duration;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.suffix = '',
    required this.style,
    this.duration = const Duration(milliseconds: 1200),
  });

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(begin: 0, end: widget.value)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedCounter old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _animation = Tween<double>(begin: _animation.value, end: widget.value)
          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) => Text(
        '${_animation.value.toStringAsFixed(1)}${widget.suffix}',
        style: widget.style,
      ),
    );
  }
}
