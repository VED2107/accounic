import 'package:flutter/material.dart';

import '../../core/demo.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../motion.dart';
import '../sheets/upgrade_sheet.dart';

/// A capability the demo does not open, shown where that capability would have
/// been (docs/demo.md).
///
/// The alternative was to delete the control and say nothing, which is worse in
/// both directions: the visitor never learns the capability exists, and the form
/// they are looking at silently becomes a smaller product than the one being
/// sold to them. This keeps the shape of the real form — the row is where the
/// field was, at the height the field was — and tells the truth about it.
///
/// It is styled as sunken and quiet on purpose. It sits inside forms the visitor
/// is trying to complete, and a bright upsell in the middle of a settlement is
/// an interruption, not an offer. It reads as a note until it is tapped.
class DemoGateRow extends StatelessWidget {
  const DemoGateRow({
    super.key,
    required this.feature,
    required this.label,
  });

  final DemoFeature feature;

  /// What the row says the visitor would be doing here. Written as the action,
  /// not as the restriction: "Settle a specific transaction", never "Targeted
  /// settlement is locked".
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Semantics(
      button: true,
      label: '$label — available in full Accounic',
      child: Pressable(
        onTap: () => showUpgradeSheet(context, feature),
        scale: 0.99,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: palette.sunken,
            borderRadius: AppRadius.fieldAll,
            border: Border.all(color: palette.line),
          ),
          child: Row(
            children: [
              Icon(AppIcons.tiers, size: AppIconSize.sm, color: palette.inkFaint),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: palette.inkMuted,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Full Accounic',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.colors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                AppIcons.forward,
                size: AppIconSize.xs,
                color: context.colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
