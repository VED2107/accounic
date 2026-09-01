/// Reading a rate provider's answer (upgrade §6, §7).
///
/// Split out of `rates_repository.dart` so the interesting failures — the ones
/// a provider hands you rather than the ones the network does: a 200 carrying
/// `result: "error"`, a rates map of strings, a zero, a null — can be tested
/// without a socket. The repository keeps the fetching; this keeps the rules.
///
/// Mirrored by `web/src/lib/rate-source.ts`.
library;

const String kPrimaryRateUrl = 'https://open.er-api.com/v6/latest';
const String kFallbackRateUrl = 'https://api.frankfurter.dev/v1/latest';

class RateTable {
  const RateTable({required this.rates, required this.asOf, required this.source});

  /// Decimal rates as published: one base unit costs this many of the quote.
  final Map<String, num> rates;
  final String asOf;
  final String source;
}

String _isoDay(Object? value) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc().toIso8601String().substring(0, 10);
  }
  return DateTime.now().toUtc().toIso8601String().substring(0, 10);
}

/// Keep only the entries that are actually numbers.
///
/// A provider that sends `"84.2"` as a string, or `null` for a currency it has
/// stopped publishing, is not a reason to throw the other 160 rates away. The
/// unusable entry is dropped and the caller finds no rate for that one pair,
/// which is the truth.
Map<String, num> ratesOnly(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, num>{};
  for (final entry in raw.entries) {
    final value = entry.value;
    if (value is num && !value.isNaN && !value.isInfinite) {
      out[entry.key.toString().toUpperCase()] = value;
    }
  }
  return out;
}

/// open.er-api.com's payload as a table, or null when it is not one.
RateTable? parsePrimaryRates(Object? payload) {
  if (payload is! Map) return null;
  if (payload['result'] != 'success') return null;
  final rates = ratesOnly(payload['rates']);
  if (rates.isEmpty) return null;
  return RateTable(
    rates: rates,
    asOf: _isoDay(payload['time_last_update_utc']),
    source: 'open.er-api.com',
  );
}

/// frankfurter.dev's payload as a table, or null when it is not one.
RateTable? parseFallbackRates(Object? payload) {
  if (payload is! Map) return null;
  final rates = ratesOnly(payload['rates']);
  if (rates.isEmpty) return null;
  final date = payload['date'];
  return RateTable(
    rates: rates,
    asOf: date is String ? date : _isoDay(null),
    source: 'frankfurter.dev (ECB)',
  );
}
