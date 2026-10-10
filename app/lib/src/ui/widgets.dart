import 'dart:async';
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
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

/// Live countdown to the next background check. Ticks only while this screen is visible.
class NextCheck extends StatefulWidget {
  const NextCheck(
    this.next, {
    super.key,
    required this.interval,
    required this.onOverdue,
    this.label = 'Next check for laptop changes',
  });

  final DateTime next;
  final Duration interval;
  final String label;

  /// Called every 15 s while overdue, to pick up a background check that just ran.
  final Future<void> Function() onOverdue;

  @override
  State<NextCheck> createState() => _NextCheckState();
}

class _NextCheckState extends State<NextCheck> {
  // Started eagerly in initState: a `late` field initialiser would only run on first read.
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {});
      if (t.tick % 15 == 0 && widget.next.isBefore(DateTime.now())) widget.onOverdue();
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final left = widget.next.difference(DateTime.now());
    final overdue = left.inSeconds <= 0;
    final progress = overdue
        ? 1.0
        : 1 - left.inMilliseconds / widget.interval.inMilliseconds;
    final mm = left.inMinutes.toString().padLeft(2, '0');
    final ss = (left.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label,
              style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(
            overdue ? 'Any moment now' : '$mm:$ss',
            style: (overdue ? theme.textTheme.headlineSmall : theme.textTheme.displayMedium)
                ?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.primary,
              height: 1.1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: scheme.surfaceContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// A unified-diff patch in its simplest readable form: added lines green, removed red,
/// context dimmed, hunk headers dropped, and cut off after [maxLines].
class DiffView extends StatelessWidget {
  const DiffView(this.patch, {super.key, this.maxLines = 30});

  final String patch;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = patch.split('\n').where((l) => !l.startsWith('@@') && !l.startsWith('\\')).toList();
    final shown = lines.take(maxLines).toList();
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.35);
    final added = Color.alphaBlend(Colors.green.withValues(alpha: 0.18), scheme.surfaceContainerHighest);
    final removed = Color.alphaBlend(Colors.red.withValues(alpha: 0.18), scheme.surfaceContainerHighest);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final l in shown)
            Container(
              color: l.startsWith('+') ? added : l.startsWith('-') ? removed : null,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
              child: Text(
                l.isEmpty ? ' ' : l,
                style: mono?.copyWith(
                  color: l.startsWith('+') || l.startsWith('-')
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (lines.length > maxLines)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Text('… ${lines.length - maxLines} more lines', style: theme.textTheme.labelMedium),
            ),
        ],
      ),
    );
  }
}
