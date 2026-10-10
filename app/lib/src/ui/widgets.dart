import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Scalloped "cookie" badge from the Material 3 Expressive shape set. While [busy] it spins
/// and morphs between two shapes, which doubles as the loading indicator.
class ShapeBadge extends StatefulWidget {
  const ShapeBadge({
    super.key,
    required this.icon,
    required this.color,
    required this.onColor,
    this.size = 96,
    this.busy = false,
  });

  final IconData icon;
  final Color color, onColor;
  final double size;
  final bool busy;

  @override
  State<ShapeBadge> createState() => _ShapeBadgeState();
}

class _ShapeBadgeState extends State<ShapeBadge> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  static const _calm = StarBorder(points: 9, innerRadiusRatio: 0.84, pointRounding: 0.6, valleyRounding: 0.4);
  static const _busy = StarBorder(points: 6, innerRadiusRatio: 0.72, pointRounding: 0.7, valleyRounding: 0.3);

  @override
  void initState() {
    super.initState();
    if (widget.busy) _spin.repeat();
  }

  @override
  void didUpdateWidget(ShapeBadge old) {
    super.didUpdateWidget(old);
    if (widget.busy && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.busy && _spin.isAnimating) {
      _spin.animateTo(1, curve: Curves.easeOutBack).then((_) => _spin.value = 0);
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Honour the system "Remove animations" setting: keep the shape, drop the spin.
    if (MediaQuery.disableAnimationsOf(context) && _spin.isAnimating) _spin.stop();
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.busy ? 1 : 0),
      duration: const Duration(milliseconds: 650),
      curve: Curves.elasticOut,
      builder: (context, morph, child) => AnimatedBuilder(
        animation: _spin,
        builder: (context, child) => Transform.rotate(
          angle: _spin.value * 2 * math.pi,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: widget.color,
              shape: ShapeBorder.lerp(_calm, _busy, morph.clamp(0, 1))!,
            ),
            child: child,
          ),
        ),
        child: child,
      ),
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: Icon(
            widget.icon,
            key: ValueKey(widget.icon),
            size: widget.size * 0.42,
            color: widget.onColor,
          ),
        ),
      ),
    );
  }
}

/// Rounded group of settings rows with a bold label above it.
class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.children, this.padding});

  final String title;
  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 10),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: padding ?? const EdgeInsets.symmetric(vertical: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tonal rounded-square icon used as the leading element of list rows.
class TonalIcon extends StatelessWidget {
  const TonalIcon(this.icon, {super.key, this.color, this.onColor});

  final IconData icon;
  final Color? color, onColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color ?? scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: onColor ?? scheme.onSecondaryContainer, size: 24),
    );
  }
}

String clockTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

String ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

String dayLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[t.month - 1]} ${t.day}${t.year == now.year ? '' : ', ${t.year}'}';
}
