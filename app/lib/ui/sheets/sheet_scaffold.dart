import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../motion.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';

/// Sheets and dialogs (context.md §18, §27).
///
/// Every transactional interaction in the product is presented through here, and
/// how it is presented depends on the width rather than on the platform:
///
/// * **Compact** — a bottom sheet. It arrives from the edge the thumb is
///   nearest, and the keyboard pushes it rather than covering it.
/// * **Wide** — a centred panel. A bottom sheet on a 2000px monitor is a phone
///   pattern wearing a desktop's clothes: it strands the content at the bottom
///   of the screen, a long way from where the user was looking.
///
/// Both are the same widget with the same chrome. Only the entrance differs.

/// Presents [builder] as a sheet or a centred panel, whichever the width calls
/// for. Returns whatever the content pops with.
///
/// **Pushed on the ROOT navigator, not the shell's.** The four destinations and
/// the docked add button belong to the application shell, and go_router builds
/// that shell around its own nested navigator. A sheet pushed there opens
/// *inside* the shell's Scaffold, which leaves the bottom bar and the `+` drawn
/// over the form — a second, meaningless bottom action area under the one the
/// form supplies itself, on the exact edge of the screen the thumb reaches for
/// Save. Rooting the route puts the form above the whole shell, so the footer
/// is gone while a form is open and back the moment it closes, with no state
/// for anyone to keep in step (upgrade §41).
Future<T?> showAppSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool dismissible = true,
}) {
  final compact = context.isCompact;

  if (compact) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: dismissible,
      enableDrag: dismissible,
      builder: builder,
    );
  }

  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: dismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: Motion.normal,
    pageBuilder: (context, _, __) => _CentredPanel(child: Builder(builder: builder)),
    transitionBuilder: (context, animation, _, child) {
      if (Motion.of(context)) return child;
      final curved = CurvedAnimation(parent: animation, curve: Motion.enter);
      return FadeTransition(
        opacity: curved,
        // Scale rather than slide: a panel that grows into place reads as
        // opening, where one that slides reads as arriving from off-screen —
        // and there is no off-screen direction that means anything here.
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// The desktop presentation: a bordered panel in the middle of the window.
class _CentredPanel extends StatelessWidget {
  const _CentredPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Material(
          color: context.money.raised,
          borderRadius: AppRadius.panelAll,
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.panelAll,
              border: Border.all(color: context.money.lineStrong),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Shared chrome for every sheet.
///
/// Handles the keyboard inset, scrolling, the header, the error line and the
/// busy state in one place, so each sheet is only its own fields.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.children,
    required this.primaryLabel,
    required this.onPrimary,
    this.subtitle,
    this.icon,
    this.error,
    this.busy = false,
    this.primaryColor,
    this.maxWidth = 480,
    this.cancelLabel = 'Cancel',
  });

  final String title;
  final String? subtitle;

  /// A glyph in a tinted square beside the title. Says what kind of thing this
  /// is before the title has been read.
  final IconData? icon;

  final List<Widget> children;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? error;
  final bool busy;
  final Color? primaryColor;
  final double maxWidth;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final palette = context.money;
    final media = MediaQuery.of(context);
    final insets = media.viewInsets.bottom;
    // The gesture bar and the notch. A sheet that ends exactly at the screen
    // edge puts its primary action under the Android navigation pill.
    final safeBottom = media.padding.bottom;

    // The height that is actually left once the keyboard has taken its share.
    // Sizing against the full screen instead is what put the actions underneath
    // the keyboard: the panel was allowed to be taller than the space it had, so
    // its foot hung below the fold.
    final available = media.size.height - insets - safeBottom;
    final maxHeight = available * (compact ? 0.94 : 0.86);

    // Cancel and the primary action are **outside** the scroll view.
    //
    // They used to be the last children inside it, which meant that whenever the
    // fields were taller than the sheet — which on a phone with a keyboard open
    // is always — the only way to reach Save was to scroll past every field. A
    // control that has to be hunted for reads as a control that is not there.
    // Pinned, they occupy the foot of the panel at every height, and the fields
    // scroll behind them.
    final footer = Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        // With the keyboard up the OS already reserves the gesture area, so
        // adding it again leaves a visible dead band under the buttons.
        AppSpacing.xl + (compact && insets == 0 ? safeBottom * 0.5 : 0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The error sits with the actions rather than up under the title, so
          // a refused save is answered where the user is looking when it is
          // refused. It animates open so the panel does not jump.
          AnimatedSize(
            duration: Motion.fast,
            curve: Motion.enter,
            alignment: Alignment.bottomCenter,
            child: error == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: ErrorNote(error!),
                  ),
          ),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  // 48dp: the Material minimum for a touch target, and this
                  // sits in the thumb zone directly above the keyboard. The
                  // default OutlinedButton is 36dp high, which is a miss
                  // waiting to happen next to a destructive neighbour.
                  height: 48,
                  // Pops *nothing*, never `false`. This chrome is shared by
                  // sheets whose routes carry different result types — the
                  // person sheet's is a `Route<Person>` — and popping a bool
                  // into one of those throws a type error instead of closing,
                  // which is exactly how Cancel came to do nothing at all.
                  // Every caller already reads a null result as "cancelled".
                  child: OutlinedButton(
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: Text(cancelLabel),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: _PrimaryButton(
                  label: primaryLabel,
                  busy: busy,
                  color: primaryColor,
                  onPressed: onPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final body = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              // Dragging the fields dismisses the keyboard, which is the
              // gesture every other Android form answers to. Without it the
              // only way out of the keyboard is the system back button, and a
              // form that traps the keyboard reads as a form that is stuck.
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl,
                compact ? AppSpacing.xs : AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (icon != null) ...[
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: palette.sunken,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: palette.line),
                          ),
                          child: Icon(icon, size: AppIconSize.md, color: palette.inkMuted),
                        ),
                        const SizedBox(width: AppSpacing.md),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(title, style: context.display(18)),
                            if (subtitle != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                subtitle!,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.45,
                                  color: palette.inkMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!compact)
                        AppIconAction(
                          icon: AppIcons.close,
                          tooltip: 'Close',
                          onPressed: busy ? null : () => Navigator.of(context).pop(),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  ...children,
                ],
              ),
            ),
          ),
          footer,
        ],
      ),
    );

    // Tapping anything that is not a field puts the keyboard away. Opaque
    // rather than deferToChild so the empty space between fields counts, and
    // translucent hit testing so the fields themselves still receive their
    // taps.
    final dismissible = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: body,
    );

    if (!compact) return dismissible;

    // AnimatedPadding rather than Padding: the keyboard opens over about
    // 250ms, and a sheet that jumps to its final position in one frame while
    // the keyboard is still sliding up reads as a glitch. It also means the
    // sheet visibly settles back down when the keyboard is dismissed, instead
    // of appearing to be stuck at keyboard height.
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Motion.enter,
      padding: EdgeInsets.only(bottom: insets),
      child: Align(alignment: Alignment.bottomCenter, child: dismissible),
    );
  }
}

/// The filled action at the foot of a sheet.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final Color? color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = !busy && onPressed != null;

    return Hoverable(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (context, hovered) => Pressable(
        onTap: enabled ? onPressed : null,
        scale: 0.985,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          height: 48,
          decoration: BoxDecoration(
            gradient: color == null && enabled ? AccounicColors.actionGradient : null,
            color: color != null
                ? (enabled ? color : color!.withValues(alpha: 0.45))
                : (enabled ? null : context.money.sunken),
            borderRadius: AppRadius.fieldAll,
            border: Border.all(
              color: enabled ? Colors.transparent : context.money.line,
            ),
            boxShadow: [
              if (hovered && enabled)
                BoxShadow(
                  color: (color ?? AccounicColors.actionGlow).withValues(alpha: 0.34),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: Motion.fast,
              child: busy
                  ? const SizedBox(
                      key: ValueKey('busy'),
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      label,
                      key: const ValueKey('label'),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: enabled ? Colors.white : context.money.inkFaint,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Confirmation (context.md §17).
///
/// A destructive confirmation is the one dialog in the product allowed to be
/// slow to accept: the glyph is tinted with the consequence, the body says what
/// actually happens rather than "are you sure?", and the confirming button
/// carries the verb rather than the word OK.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = true,
  IconData? icon,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    // Above the shell, like every other modal in the product.
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: Motion.normal,
    pageBuilder: (dialogContext, _, __) => _ConfirmDialog(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      icon: icon,
    ),
    transitionBuilder: (context, animation, _, child) {
      if (Motion.of(context)) return child;
      final curved = CurvedAnimation(parent: animation, curve: Motion.enter);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
  return result ?? false;
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
    required this.icon,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final accent = destructive ? palette.payable : context.colors.primary;
    final soft = destructive ? palette.payableSoft : palette.accentSoft;
    final line = destructive ? palette.payableLine : palette.accentLine;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Material(
          color: palette.raised,
          borderRadius: AppRadius.panelAll,
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(AppSpacing.xl + 2),
            decoration: BoxDecoration(
              borderRadius: AppRadius.panelAll,
              border: Border.all(color: palette.lineStrong),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: soft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: line),
                  ),
                  child: Icon(
                    icon ?? (destructive ? AppIcons.warning : AppIcons.success),
                    size: AppIconSize.lg,
                    color: accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(title, style: context.display(18)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  body,
                  style: TextStyle(fontSize: 13.5, height: 1.55, color: palette.inkMuted),
                ),
                const SizedBox(height: AppSpacing.xl + 2),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(cancelLabel),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _PrimaryButton(
                        label: confirmLabel,
                        busy: false,
                        color: destructive ? palette.payable : null,
                        onPressed: () {
                          Haptics.selection();
                          Navigator.of(context).pop(true);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
