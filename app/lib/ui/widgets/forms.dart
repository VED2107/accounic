import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../motion.dart';

/// Form and settings components (context.md §18, §27).
///
/// Material's own `TextField` decoration is competent and completely anonymous:
/// a label that floats, a border that snaps to the accent, and no state between
/// "fine" and "error". These are the same controls with the states the product
/// actually has — resting, hovered, focused, invalid — and with the transitions
/// between them, because a border that snaps reads as a redraw and a border
/// that eases reads as a response.

/// A labelled text field that shows where the keyboard is.
///
/// The focus treatment is a ring rather than a thicker border: thickening a
/// border moves the text inside it by a pixel, which is visible and cheap-
/// looking. The ring is drawn outside the box and moves nothing.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.error,
    this.icon,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.autofocus = false,
    this.enabled = true,
    this.maxLength,
    this.maxLines = 1,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
    this.focusNode,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;

  /// A quiet line under the field. Replaced by [error] when there is one, so
  /// the field never grows or shrinks as validation comes and goes.
  final String? helper;
  final String? error;
  final IconData? icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool autofocus;
  final bool enabled;
  final int? maxLength;
  final int maxLines;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  /// Supplied by forms that hand focus from one field to the next, so the
  /// keyboard's Next key goes somewhere instead of doing nothing.
  final FocusNode? focusNode;
  final TextCapitalization textCapitalization;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  /// Only owned when the caller did not supply one — disposing a node the
  /// parent still holds would take the whole form down with it.
  FocusNode? _owned;
  FocusNode get _focus => widget.focusNode ?? (_owned ??= FocusNode());
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted && _focused != _focus.hasFocus) {
        setState(() => _focused = _focus.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final invalid = widget.error != null;

    final border = invalid
        ? palette.payable
        : _focused
            ? context.colors.primary
            : palette.line;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                  color: _focused ? context.colors.onSurface : palette.inkMuted,
                ),
              ),
            ),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
        const SizedBox(height: AppSpacing.sm - 2),
        Hoverable(
          cursor: SystemMouseCursors.text,
          builder: (context, hovered) => AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.enter,
            decoration: BoxDecoration(
              color: widget.enabled ? palette.sunken : palette.sunken.withValues(alpha: 0.5),
              borderRadius: AppRadius.fieldAll,
              border: Border.all(
                color: !_focused && hovered && !invalid ? palette.lineStrong : border,
              ),
              boxShadow: [
                if (_focused)
                  BoxShadow(
                    color: (invalid ? palette.payable : context.colors.primary)
                        .withValues(alpha: 0.16),
                    blurRadius: 0,
                    spreadRadius: 3,
                  ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.icon != null)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.md, right: 2),
                    child: Icon(
                      widget.icon,
                      size: AppIconSize.sm,
                      color: _focused ? context.colors.primary : palette.inkFaint,
                    ),
                  ),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    autofocus: widget.autofocus,
                    obscureText: widget.obscureText,
                    keyboardType: widget.keyboardType,
                    textInputAction: widget.textInputAction,
                    maxLength: widget.maxLength,
                    maxLines: widget.maxLines,
                    inputFormatters: widget.inputFormatters,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    textCapitalization: widget.textCapitalization,
                    style: const TextStyle(fontSize: 14.5),
                    cursorColor: context.colors.primary,
                    cursorWidth: 1.5,
                    cursorRadius: const Radius.circular(2),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      counterText: '',
                      filled: false,
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: EdgeInsets.fromLTRB(
                        widget.icon == null ? AppSpacing.md + 2 : AppSpacing.sm + 2,
                        13,
                        AppSpacing.md + 2,
                        13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // The two lines occupy the same slot and cross-fade, so validation
        // never pushes the field below it down the page.
        AnimatedSize(
          duration: Motion.fast,
          curve: Motion.enter,
          alignment: Alignment.topLeft,
          child: (widget.error ?? widget.helper) == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm - 2, left: 2),
                  child: AnimatedSwitcher(
                    duration: Motion.fast,
                    child: Row(
                      key: ValueKey(widget.error ?? widget.helper),
                      children: [
                        if (invalid) ...[
                          Icon(AppIcons.warning, size: AppIconSize.xs - 2, color: palette.payable),
                          const SizedBox(width: AppSpacing.xs + 1),
                        ],
                        Expanded(
                          child: Text(
                            widget.error ?? widget.helper!,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: invalid ? palette.payable : palette.inkFaint,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// A labelled dropdown built to match [AppTextField] exactly.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.icon,
    this.helper,
  });

  final String label;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T?> onChanged;
  final IconData? icon;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: palette.inkMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.sm - 2),
        Hoverable(
          builder: (context, hovered) => AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.enter,
            height: 46,
            padding: EdgeInsets.only(left: icon == null ? AppSpacing.md + 2 : AppSpacing.md),
            decoration: BoxDecoration(
              color: palette.sunken,
              borderRadius: AppRadius.fieldAll,
              border: Border.all(color: hovered ? palette.lineStrong : palette.line),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: AppIconSize.sm, color: palette.inkFaint),
                  const SizedBox(width: AppSpacing.sm + 2),
                ],
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<T>(
                      value: value,
                      isExpanded: true,
                      icon: Icon(AppIcons.expand, size: AppIconSize.sm, color: palette.inkFaint),
                      borderRadius: AppRadius.fieldAll,
                      dropdownColor: palette.raised,
                      style: TextStyle(fontSize: 14.5, color: context.colors.onSurface),
                      onChanged: onChanged,
                      items: [
                        for (final (item, label) in items)
                          DropdownMenuItem(value: item, child: Text(label)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ),
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: AppSpacing.sm - 2),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              helper!,
              style: TextStyle(fontSize: 12, height: 1.4, color: palette.inkFaint),
            ),
          ),
        ],
      ],
    );
  }
}

/// What a submit button is doing right now.
enum SaveState { idle, saving, saved }

/// A primary button that reports the outcome of what it started.
///
/// The saved state holds for a beat and then returns to idle on its own. A
/// spinner that vanishes and leaves the form exactly as it was is the most
/// common way an application fails to answer "did that work?", and a toast an
/// eye-line away from the button is only half an answer.
class SaveButton extends StatelessWidget {
  const SaveButton({
    super.key,
    required this.state,
    required this.onPressed,
    this.label = 'Save',
    this.savedLabel = 'Saved',
    this.expand = false,
  });

  final SaveState state;
  final VoidCallback? onPressed;
  final String label;
  final String savedLabel;

  /// Full width. Off by default — a full-width primary button on a 640px form
  /// is a web pattern, and it makes a settings page look like a landing page.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final saved = state == SaveState.saved;
    final busy = state == SaveState.saving;

    final button = Hoverable(
      builder: (context, hovered) => Pressable(
        onTap: busy || saved ? null : onPressed,
        scale: 0.985,
        child: AnimatedContainer(
          duration: Motion.normal,
          curve: Motion.enter,
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          decoration: BoxDecoration(
            gradient: saved ? null : AccounicColors.actionGradient,
            color: saved ? context.money.receivableSoft : null,
            borderRadius: AppRadius.fieldAll,
            border: Border.all(
              color: saved ? context.money.receivableLine : Colors.transparent,
            ),
            boxShadow: [
              if (hovered && !saved && !busy)
                BoxShadow(
                  color: const Color(0xFF1D4ED8).withValues(alpha: 0.34),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: Motion.fast,
              child: switch (state) {
                SaveState.saving => const SizedBox(
                    key: ValueKey('saving'),
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                SaveState.saved => Row(
                    key: const ValueKey('saved'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.check, size: AppIconSize.sm, color: context.money.receivable),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        savedLabel,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: context.money.receivable,
                        ),
                      ),
                    ],
                  ),
                SaveState.idle => Text(
                    label,
                    key: const ValueKey('idle'),
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
              },
            ),
          ),
        ),
      ),
    );

    return expand ? button : Align(alignment: Alignment.centerLeft, child: button);
  }
}

/// A group of settings rows under one heading.
///
/// The heading sits *outside* the card, which is what separates a settings page
/// from a form: the card is the control surface and the heading is the label on
/// it, so a page of five groups reads as five things rather than five boxes.
///
/// On a desktop width the heading moves to its own column beside the card. A
/// 640px form column on a 1500px window leaves two thirds of the screen empty;
/// putting the label and its explanation in that space uses the width for
/// something a reader wants, rather than padding it out or — worse — stretching
/// a name field to a thousand pixels.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.children,
    this.description,
  });

  final String title;
  final String? description;
  final List<Widget> children;

  /// The width of the label column, and the point below which there is not
  /// enough room for two columns to be worth having.
  static const double _labelColumn = 232;

  @override
  Widget build(BuildContext context) {
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: context.money.inkFaint,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: AppSpacing.sm - 2),
          Text(
            description!,
            style: TextStyle(fontSize: 12.5, height: 1.5, color: context.money.inkMuted),
          ),
        ],
      ],
    );

    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );

    if (!context.isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.md),
            child: label,
          ),
          card,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelColumn,
          // Optically aligned with the first control inside the card rather
          // than with the card's top edge.
          child: Padding(padding: const EdgeInsets.only(top: AppSpacing.xl), child: label),
        ),
        const SizedBox(width: AppSpacing.xxl),
        Expanded(child: card),
      ],
    );
  }
}

/// One row inside a [SettingsGroup]: a glyph, what it is, and where it goes.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.tone,
    this.trailing,
    this.divider = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Overrides the ink colour — used for sign out and for destructive rows.
  final Color? tone;
  final Widget? trailing;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final color = tone ?? context.colors.onSurface;

    return Column(
      children: [
        Hoverable(
          builder: (context, hovered) => AnimatedContainer(
            duration: Motion.fast,
            color: hovered && onTap != null ? palette.sunken : Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md + 2,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: AppIconSize.md, color: tone ?? palette.inkMuted),
                    const SizedBox(width: AppSpacing.md + 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) trailing!,
                    if (onTap != null && trailing == null)
                      AnimatedSlide(
                        duration: Motion.fast,
                        curve: Motion.enter,
                        offset: Offset(hovered ? 0.18 : 0, 0),
                        child: Icon(
                          AppIcons.forward,
                          size: AppIconSize.sm,
                          color: palette.inkFaint,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (divider) Divider(height: 1, color: palette.line, indent: AppSpacing.lg),
      ],
    );
  }
}

/// The content of a settings card that is a form rather than a list of rows.
class SettingsForm extends StatelessWidget {
  const SettingsForm({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: context.cardPadding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// A group of related fields under one heading (upgrade §1).
///
/// A sheet of nine controls where every control looks alike is nine decisions
/// presented at once. Grouped — identity, currency, opening balance, contact —
/// it is four, and each can be read and dismissed before the next.
///
/// The heading is a hairline label rather than a card. Boxing every group would
/// put six borders on one form and make a sheet read as a settings page; the
/// rule above each group separates them with a single pixel instead. This is
/// the Flutter half of the web's `FormSection`, and the two are deliberately
/// the same shape.
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
    this.aside,
    this.first = false,
  });

  final String title;
  final String? description;

  /// A short right-aligned note beside the heading — "Optional", a currency
  /// code, a count.
  final String? aside;
  final List<Widget> children;

  /// The first section in a form drops its rule: there is nothing above it to
  /// be separated from.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!first) ...[
          const SizedBox(height: AppSpacing.lg),
          Divider(height: 1, thickness: 1, color: palette.line),
          const SizedBox(height: AppSpacing.lg),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                      color: palette.inkFaint,
                    ),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: AppSpacing.xs + 1),
                    Text(
                      description!,
                      style: TextStyle(fontSize: 12.5, height: 1.5, color: palette.inkMuted),
                    ),
                  ],
                ],
              ),
            ),
            if (aside != null)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.md),
                child: Text(
                  aside!,
                  style: TextStyle(fontSize: 12, color: palette.inkFaint),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ...children,
      ],
    );
  }
}

/// A quiet explanatory block inside a form — what a choice will do, what a
/// refusal means. Not an error and not a card: one tone below the field it
/// qualifies.
class FormNote extends StatelessWidget {
  const FormNote({
    super.key,
    required this.child,
    this.title,
    this.accent = false,
  });

  final String? title;
  final Widget child;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      decoration: BoxDecoration(
        color: accent ? palette.accentSoft : palette.sunken,
        borderRadius: AppRadius.fieldAll,
        border: Border.all(color: accent ? palette.accentLine : palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.45,
                color: context.colors.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          child,
        ],
      ),
    );
  }
}
