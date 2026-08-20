import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money.dart';
import '../../core/theme.dart';

/// The amount field (context.md §7, §14).
///
/// A text field, never a numeric stepper: the user types digits and a decimal
/// point, and [parseAmountToMinor] turns that into integer minor units. The
/// widget never holds a double, and the value it reports is always an int.
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
      TextEditingController(text: widget.initial == null ? '' : minorToInput(widget.initial!));
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

    final minor = parseAmountToMinor(raw);
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

  void _fillMax() {
    final max = widget.maxMinor;
    if (max == null) return;
    _controller.text = minorToInput(max);
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
            FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            LengthLimitingTextInputFormatter(16),
          ],
          onChanged: _handle,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
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
                  fontSize: 20,
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
        if (widget.maxMinor != null && !invalid) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: _fillMax,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Settle the full ${formatMinor(widget.maxMinor!, currency: widget.currency)}',
            ),
          ),
        ],
      ],
    );
  }
}
