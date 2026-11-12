import 'package:flutter/material.dart';

import '../theme/marketplace_theme.dart';

class MarketplaceSectionHeader extends StatelessWidget {
  const MarketplaceSectionHeader(
    this.title, {
    super.key,
    this.subtitle,
    this.icon,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 16),
    child: Row(
      children: [
        if (icon != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.mint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.forest, size: 22),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class MarketplaceEmptyState extends StatelessWidget {
  const MarketplaceEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppColors.mint,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: AppColors.green),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    ),
  );
}

class MarketplaceListingCard extends StatelessWidget {
  const MarketplaceListingCard({
    super.key,
    required this.title,
    required this.price,
    required this.location,
    required this.isService,
    this.imageUrl,
    this.onTap,
    this.trailing,
  });
  final String title, price, location;
  final bool isService;
  final String? imageUrl;
  final VoidCallback? onTap;
  final Widget? trailing;

  Widget _placeholder() => ColoredBox(
    color: AppColors.mint,
    child: Center(
      child: Icon(
        isService ? Icons.handyman_outlined : Icons.storefront_outlined,
        size: 40,
        color: AppColors.green,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl == null || imageUrl!.isEmpty)
                  _placeholder()
                else
                  Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    cacheWidth: 800,
                    errorBuilder: (_, _, _) => _placeholder(),
                    frameBuilder: (context, child, frame, sync) =>
                        frame == null ? _placeholder() : child,
                  ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      child: Text(
                        isService ? 'SERVICE' : 'PRODUCT',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.forest,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                ),
                if (trailing != null)
                  Positioned(right: 8, top: 8, child: trailing!),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  price,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.forest,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 15,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Finite entrances avoid permanent ticker work and honour reduced motion.
class MarketplaceEntrance extends StatelessWidget {
  const MarketplaceEntrance({super.key, required this.child, this.delay = 0});
  final Widget child;
  final int delay;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + delay),
      curve: Interval(delay / (420 + delay), 1, curve: Curves.easeOutCubic),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
