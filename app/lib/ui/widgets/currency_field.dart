import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currencies.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import 'forms.dart';

/// Choosing a currency (upgrade §1, §19).
///
/// A dropdown built to match [AppTextField] exactly, so a form that mixes the
/// two does not read as two form libraries stitched together. Every option
/// leads with the ISO code, because a symbol is not an identifier — `$` is four
/// different currencies in this list alone.
class CurrencyField extends StatelessWidget {
  const CurrencyField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Currency',
    this.helper,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String label;
  final String? helper;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final current = normaliseCode(value);

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
        Container(
          height: 46,
          padding: const EdgeInsets.only(left: AppSpacing.md),
          decoration: BoxDecoration(
            color: enabled ? palette.sunken : palette.sunken.withValues(alpha: 0.5),
            borderRadius: AppRadius.fieldAll,
            border: Border.all(color: palette.line),
          ),
          child: Row(
            children: [
              Text(
                currencyOf(current)?.symbol ?? current,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: palette.inkFaint,
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: currencyOf(current) == null ? kFallbackCurrency : current,
                    isExpanded: true,
                    icon: Icon(AppIcons.expand, size: AppIconSize.sm, color: palette.inkFaint),
                    borderRadius: AppRadius.fieldAll,
                    dropdownColor: palette.raised,
                    style: TextStyle(fontSize: 14.5, color: context.colors.onSurface),
                    onChanged: enabled ? (next) => onChanged(next ?? current) : null,
                    // The selected row shows the code alone: the full label is
                    // useful while choosing and noise once chosen.
                    selectedItemBuilder: (context) => [
                      for (final currency in kCurrencies)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${currency.code} · ${currency.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14.5),
                          ),
                        ),
                    ],
                    items: [
                      for (final currency in kCurrencies)
                        DropdownMenuItem(
                          value: currency.code,
                          child: Text(currency.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
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

/// Live conversion for a cross-currency entry (upgrade §5, §11, §40).
///
/// The rule this is built around: never hide what was actually exchanged. Both
/// figures stay on screen, the rate linking them is spelled out, and whether it
/// is live, cached or stale is said in words rather than implied by an icon.
///
/// Since v1.1.2 there are *two* things "what was actually exchanged" can mean.
/// The rate says Rs 1,000 is AED 44.20; the exchange counter handed over
/// AED 43. Both are true, and this panel lets the user say which one the ledger
/// takes without ever discarding the other. Automatic stays the default —
/// nobody should have to fight the conversion to record an ordinary entry.
///
/// The automatic figure here is a preview: the database recomputes it from the
/// same amount and the same rate. The manual figure is not a preview, because
/// it is not derived from anything — it is what the user says happened, so it
/// travels, with the automatic one beside it as the audit reference.
class ConversionPanel extends ConsumerStatefulWidget {
  const ConversionPanel({
    super.key,
    required this.amountMinor,
    required this.from,
    required this.to,
    required this.manual,
    required this.onManualChanged,
    required this.onActualChanged,
    this.initialActualMinor,
  });

  final int? amountMinor;
  final String from;
  final String to;

  /// Whether the override is switched on. Owned by the sheet, because the sheet
  /// is what has to send it.
  final bool manual;
  final ValueChanged<bool> onManualChanged;

  /// The actual amount in [to], or null when it is empty or unparseable.
  final ValueChanged<int?> onActualChanged;

  /// Reopening an entry that was already overridden starts on its own figure.
  final int? initialActualMinor;

  @override
  ConsumerState<ConversionPanel> createState() => _ConversionPanelState();
}

class _ConversionPanelState extends ConsumerState<ConversionPanel> {
  late final TextEditingController _actual = TextEditingController(
    text: widget.initialActualMinor == null
        ? ''
        : minorToInput(widget.initialActualMinor!, currency: normaliseCode(widget.to)),
  );
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialActualMinor != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handle(_actual.text));
    }
  }

  @override
  void dispose() {
    _actual.dispose();
    super.dispose();
  }

  void _handle(String raw) {
    final target = normaliseCode(widget.to);
    if (raw.trim().isEmpty) {
      setState(() => _error = null);
      widget.onActualChanged(null);
      return;
    }
    // Parsed against the ACCOUNT currency, never the entry one: this is the
    // amount that landed in the account, which is the whole point of it.
    // Getting that pair the wrong way round is how AED 43 becomes Rs 43.
    final minor = parseAmountToMinor(raw, currency: target);
    if (minor == null || minor <= 0) {
      setState(() => _error = 'Enter a valid $target amount');
      widget.onActualChanged(null);
      return;
    }
    setState(() => _error = null);
    widget.onActualChanged(minor);
  }

  @override
  Widget build(BuildContext context) {
    final source = normaliseCode(widget.from);
    final target = normaliseCode(widget.to);
    if (source.isEmpty || target.isEmpty || source == target) {
      return const SizedBox.shrink();
    }

    final palette = context.money;
    final rate = ref.watch(rateProvider((from: source, to: target)));

    return rate.when(
      loading: () => _Frame(
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'Fetching today’s $source → $target rate…',
                style: TextStyle(fontSize: 12.5, color: palette.inkMuted),
              ),
            ),
          ],
        ),
      ),
      error: (_, __) => _Unavailable(from: source, to: target),
      data: (quote) {
        if (quote == null) return _Unavailable(from: source, to: target);

        final automatic = widget.amountMinor == null
            ? null
            : convertMinor(widget.amountMinor!, source, target, quote.rateE9);

        return _Frame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.manual ? 'Actual amount' : 'Converted amount',
                      style: TextStyle(fontSize: 12.5, color: palette.inkMuted),
                    ),
                  ),
                  if (!widget.manual)
                    Text(
                      automatic == null
                          ? '—'
                          : formatMinor(automatic, currency: target, withCode: true),
                      style: context.display(17).copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                ],
              ),
              if (widget.manual) ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _actual,
                  onChanged: _handle,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: context.display(17).copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                  decoration: InputDecoration(
                    prefixText: '$target ',
                    hintText:
                        automatic == null ? '0' : minorToInput(automatic, currency: target),
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm - 2),
                Text(
                  'Manual override',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.colors.primary,
                  ),
                ),
                Text(
                  'Automatic estimate: '
                  '${automatic == null ? '—' : formatMinor(automatic, currency: target, withCode: true)}'
                  ' · ${rateSentence(source, target, quote.rateE9)}',
                  style: TextStyle(fontSize: 12, height: 1.4, color: palette.inkFaint),
                ),
              ] else ...[
                const SizedBox(height: AppSpacing.sm - 2),
                Text(
                  'Automatic',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.inkMuted,
                  ),
                ),
                Text(
                  rateSentence(source, target, quote.rateE9),
                  style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
                ),
                Text(
                  quote.provenance,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: quote.stale ? FontWeight.w600 : FontWeight.w400,
                    color: quote.stale ? palette.payable : palette.inkFaint,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    // Turning the override on pre-fills the automatic figure, so
                    // the user edits a number rather than facing an empty box —
                    // the common case is "nearly that, but 43".
                    if (!widget.manual && _actual.text.trim().isEmpty && automatic != null) {
                      _actual.text = minorToInput(automatic, currency: target);
                      _handle(_actual.text);
                    }
                    widget.onManualChanged(!widget.manual);
                  },
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  ),
                  child: Text(
                    widget.manual ? 'Use the automatic conversion' : 'Use actual amount',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md + 2,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: context.money.sunken,
        borderRadius: AppRadius.fieldAll,
        border: Border.all(color: context.money.line),
      ),
      child: child,
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.from, required this.to});

  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md + 2,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: palette.payableSoft,
        borderRadius: AppRadius.fieldAll,
        border: Border.all(color: palette.payableLine),
      ),
      child: Text(
        'No $from → $to rate is available, and none is cached on this account. '
        'Enter the amount in $to instead — nothing is lost, and the $from figure '
        'can go in the note.',
        style: TextStyle(fontSize: 12.5, height: 1.45, color: palette.payable),
      ),
    );
  }
}

/// What was actually handed over, shown under a stored entry.
///
/// When the converted figure was overridden by hand, that is said here too —
/// otherwise the timeline shows a number that the stated rate does not explain,
/// which reads as an arithmetic error rather than as a decision.
class ConvertedFrom extends StatelessWidget {
  const ConvertedFrom({
    super.key,
    required this.enteredMinor,
    required this.enteredCurrency,
    required this.rateE9,
    required this.accountCurrency,
    this.conversionMode,
    this.autoConvertedMinor,
  });

  final int? enteredMinor;
  final String? enteredCurrency;
  final int? rateE9;
  final String accountCurrency;
  final String? conversionMode;
  final int? autoConvertedMinor;

  @override
  Widget build(BuildContext context) {
    final entered = enteredMinor;
    final currency = enteredCurrency;
    if (entered == null || currency == null) return const SizedBox.shrink();

    final rate = rateE9;
    final buffer = StringBuffer(formatMinor(entered, currency: currency, withCode: true));
    if (rate != null) {
      buffer.write(' · ${rateSentence(currency, accountCurrency, rate)}');
    }
    if (conversionMode == 'manual') {
      buffer.write(' · Manually entered');
      final auto = autoConvertedMinor;
      if (auto != null) {
        buffer.write(
          ' (rate said ${formatMinor(auto, currency: accountCurrency, withCode: true)})',
        );
      }
    }

    return Text(
      buffer.toString(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11.5,
        color: conversionMode == 'manual'
            ? context.colors.primary
            : context.money.inkFaint,
      ),
    );
  }
}
