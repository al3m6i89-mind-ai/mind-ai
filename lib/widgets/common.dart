import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../features/paywall/paywall_screen.dart';
import '../services/subscription_service.dart';

class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, this.style, this.gradient = MindColors.brand});
  final String text;
  final TextStyle? style;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (b) => gradient.createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
        child: Text(text, style: style),
      );
}

class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.gradient = MindColors.brand,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Gradient gradient;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: MindColors.pink.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  else if (icon != null)
                    Icon(icon, color: Colors.white, size: 20),
                  if (loading || icon != null) const SizedBox(width: 8),
                  Text(label,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Colorful square tile used on the home screen and in the studio.
class ToolTile extends StatelessWidget {
  const ToolTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.gradient,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final String emoji;
  final Gradient gradient;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
                  const Spacer(),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                      child: Text(badge!,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: MindColors.pink)),
                    ),
                ],
              ),
              const Spacer(),
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a friendly error, and an upgrade button when a daily limit is hit.
void showError(BuildContext context, Object e) {
  final quota = e is QuotaExceeded;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(e.toString().replaceFirst('Exception: ', '')),
      behavior: SnackBarBehavior.floating,
      action: quota
          ? SnackBarAction(
              label: 'ترقية',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaywallScreen())),
            )
          : null,
    ),
  );
}

/// Small pill showing how many uses remain today.
class QuotaPill extends StatelessWidget {
  const QuotaPill(this.usage, {super.key});
  final Usage usage;

  @override
  Widget build(BuildContext context) {
    final subs = context.watch<SubscriptionService>();
    final left = subs.limit(usage) < 0 ? '∞' : '${subs.remaining(usage)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: MindColors.violet.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('متبقي اليوم: $left',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MindColors.violet)),
    );
  }
}
