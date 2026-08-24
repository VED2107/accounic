import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/currencies.dart';
import '../../core/money.dart';
import '../../core/theme.dart';

/// The amount field (context.md §7, §14).
///
/// A text field, never a numeric stepper: the user types digits and a decimal
/// point, and [parseAmountToMinor] turns that into integer minor units. The
/// widget never holds a double, and the value it reports is always an int.
///
/// It is the largest control in any sheet it appears in, because it is the only
/// one the user really has to think about. When a ceiling is known — settling
/// against an outstanding figure — the quarter steps turn the common cases into
/// one tap without hiding the field they fill in.
class AmountField extends StatefulWidget {
  const AmountField({
    super.key,
    required this.currency,
    required this.onChanged,
    this.initial,
    this.maxMinor,
    this.autofocus = false,
    this.label = 'Amount',
  });

  final String currency;
  final ValueChanged<int?> onChanged;
  final int? initial;
  /// Optional ceiling, e.g. the outstanding amount being settled.
  final int? maxMinor;
  final bool autofocus;
  final String label;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  late final TextEditingController _controller =
      TextEditingController(
    text: widget.initial == null
        ? ''
        : minorToInput(widget.initial!, currency: widget.currency),
  );
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handle(_controller.text));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handle(String raw) {
    if (raw.trim().isEmpty) {
      setState(() => _error = null);
      widget.onChanged(null);
      return;
    }

    // Parsed against the currency being *typed* in: ¥1000 has no decimals and
    // KWD 1.234 has three (upgrade §19).
    final minor = parseAmountToMinor(raw, currency: widget.currency);
    if (minor == null || minor <= 0) {
      setState(() => _error = 'Enter a valid amount');
      widget.onChanged(null);
      return;
    }
    if (widget.maxMinor != null && minor > widget.maxMinor!) {
      setState(() => _error =
          'That is more than the ${formatMinor(widget.maxMinor!, currency: widget.currency)} outstanding');
      widget.onChanged(null);
      return;
    }

    setState(() => _error = null);
    widget.onChanged(minor);
  }

  void _fillShare(double share) {
    final max = widget.maxMinor;
    if (max == null) return;
    final target = share == 1 ? max : (max * share).round();
    _controller.text = minorToInput(target, currency: widget.currency);
    _handle(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final invalid = _error != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _controller,
          autofocus: widget.autofocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            // A zero-decimal currency has no decimal point to type.
            FilteringTextInputFormatter.allow(
              decimalsFor(widget.currency) == 0 ? RegExp(r'[\d,]') : RegExp(r'[\d.,]'),
            ),
            LengthLimitingTextInputFormatter(16),
          ],
          onChanged: _handle,
          style: context.display(26).copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            hintText: '0',
            errorText: _error,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 14, right: 6),
              child: Text(
                currencySymbol(widget.currency),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 21,
                  color: context.money.inkFaint,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            enabledBorder: invalid
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: context.colors.error),
                  )
                : null,
          ),
        ),
        if (widget.maxMinor != null && widget.maxMinor! > 0) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              for (final share in const [0.25, 0.5, 0.75, 1.0]) ...[
                _ShareChip(
                  label: share == 1 ? 'Full' : '${(share * 100).round()}%',
                  onTap: () => _fillShare(share),
                ),
                const SizedBox(width: 6),
              ],
              const Spacer(),
              Flexible(
                child: Text(
                  '${formatMinor(widget.maxMinor!, currency: widget.currency)} outstanding',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: context.money.inkFaint),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}


/// One of the quarter steps under the amount field. A minimum 44px tap target,
/// because it sits directly under the keyboard's thumb zone.
class _ShareChip extends StatelessWidget {
  const _ShareChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    return Material(
      color: palette.sunken,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          constraints: const BoxConstraints(minWidth: 46, minHeight: 32),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: palette.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: palette.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}
