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

/// Live conversion for a cross-currency entry (upgrade §5, §11).
///
/// The rule this is built around: never hide what was actually exchanged. Both
/// figures stay on screen, the rate linking them is spelled out, and whether it
/// is live, cached or stale is said in words rather than implied by an icon.
///
/// The converted figure here is a preview. What gets stored is computed by the
/// database from the same amount and the same rate, so the number the user
/// approved is the number that lands.
class ConversionNote extends ConsumerWidget {
  const ConversionNote({
    super.key,
    required this.amountMinor,
    required this.from,
    required this.to,
  });

  final int? amountMinor;
  final String from;
  final String to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = normaliseCode(from);
    final target = normaliseCode(to);
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

        final converted = amountMinor == null
            ? null
            : convertMinor(amountMinor!, source, target, quote.rateE9);

        return _Frame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Recorded as',
                      style: TextStyle(fontSize: 12.5, color: palette.inkMuted),
                    ),
                  ),
                  Text(
                    converted == null
                        ? '—'
                        : formatMinor(converted, currency: target, withCode: true),
                    style: context.display(17).copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm - 2),
              Text(
                quote.sentence,
                style: TextStyle(fontSize: 12, color: palette.inkFaint),
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
class ConvertedFrom extends StatelessWidget {
  const ConvertedFrom({
    super.key,
    required this.enteredMinor,
    required this.enteredCurrency,
    required this.rateE9,
    required this.accountCurrency,
  });

  final int? enteredMinor;
  final String? enteredCurrency;
  final int? rateE9;
  final String accountCurrency;

  @override
  Widget build(BuildContext context) {
    final entered = enteredMinor;
    final currency = enteredCurrency;
    if (entered == null || currency == null) return const SizedBox.shrink();

    final rate = rateE9;
    final text = rate == null
        ? formatMinor(entered, currency: currency, withCode: true)
        : '${formatMinor(entered, currency: currency, withCode: true)} · '
            '${rateSentence(currency, accountCurrency, rate)}';

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11.5, color: context.money.inkFaint),
    );
  }
}
