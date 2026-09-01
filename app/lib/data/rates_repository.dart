import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/currencies.dart';
import 'rate_source.dart';

/// Exchange rates (upgrade §6, §7).
///
/// Two free, key-less sources, in this order:
///
///   1. open.er-api.com — the open endpoint of ExchangeRate-API. Daily rates,
///      no key, and 160-odd currencies, which is what settles it: the Gulf
///      currencies this product is actually used with (AED, SAR, QAR, KWD) are
///      not published by the ECB at all.
///   2. api.frankfurter.dev — ECB reference rates. Narrower coverage, but an
///      impeccable source and a useful second opinion when the first is down.
///
/// Three caches, in order of how far they are from the user:
///
///   * in memory, for the life of the process, so typing an amount does not
///     issue a request per keystroke;
///   * `public.exchange_rates` in the database, which is per-owner and
///     therefore shared with the same user's web and desktop clients — a rate
///     fetched on the phone this morning is on the desktop this afternoon;
///   * the network, at most once every twelve hours per base currency.
///
/// A missing rate never loses a transaction. It means the amount has to be
/// entered in the account's own currency, which the sheet says plainly, and the
/// entry saves normally.
///
/// `dart:io` rather than a package: this needs one GET and a JSON decode on
/// Android and Windows, and a dependency for that would be one more thing in
/// the release build to no end.
class RatesRepository {
  RatesRepository(this._client);

  final SupabaseClient _client;

  /// How long a cached rate is current before a refresh is attempted.
  static const _freshFor = Duration(hours: 12);

  /// A slow rate API must never slow down a save.
  static const _timeout = Duration(seconds: 4);

  final Map<String, RateQuote> _memory = {};

  /// The rate for [from] -> [to], or null when there is none and none can be
  /// fetched. Callers treat null as "cannot convert", never as zero.
  Future<RateQuote?> rate(String from, String to) async {
    final source = normaliseCode(from);
    final target = normaliseCode(to);
    if (source.isEmpty || target.isEmpty) return null;
    if (source == target) return RateQuote.identity(source);
    if (!isSupportedCurrency(source) || !isSupportedCurrency(target)) return null;

    final key = '$source>$target';
    final remembered = _memory[key];
    if (remembered != null && !remembered.isOlderThan(_freshFor)) return remembered;

    final cached = await _cached(source, target);
    if (cached != null && !cached.isOlderThan(_freshFor)) {
      _memory[key] = cached;
      return cached;
    }

    final table = await _fetch(source);
    final live = table == null ? null : usableRateToE9(table.rates[target]);
    if (table != null && live != null) {
      // Cache the whole table, not just the pair asked for: the payload is
      // already here, and the next currency the user picks is then free.
      await _store(source, table);
      final quote = RateQuote(
        from: source,
        to: target,
        rateE9: live,
        asOf: table.asOf,
        source: table.source,
        fetchedAt: DateTime.now(),
        cached: false,
      );
      _memory[key] = quote;
      return quote;
    }

    // Offline, the source does not publish this pair, or it published a figure
    // that is not a rate. Whatever is cached beats refusing to show the user a
    // number — it is simply labelled as cached, and as stale when it is.
    if (cached != null) {
      _memory[key] = cached;
      return cached;
    }
    return null;
  }

  /// Warm the cache for one base currency without waiting on the result.
  ///
  /// Called when a screen that is likely to need conversions opens, so the
  /// first keystroke in the amount field is not the thing that triggers a
  /// network round trip.
  Future<void> warm(String base) async {
    final code = normaliseCode(base);
    if (!isSupportedCurrency(code)) return;
    final table = await _fetch(code);
    if (table != null) await _store(code, table);
  }

  /* ---------------------------------------------------------------------- */

  Future<RateQuote?> _cached(String from, String to) async {
    try {
      final rows = await _client
          .from('exchange_rates')
          .select('base, quote, rate_e9, as_of, source, fetched_at')
          .inFilter('base', [from, to])
          .inFilter('quote', [from, to]);

      Map<String, dynamic>? direct;
      Map<String, dynamic>? inverse;
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        if (map['base'] == from && map['quote'] == to) direct = map;
        if (map['base'] == to && map['quote'] == from) inverse = map;
      }

      final row = direct ?? inverse;
      if (row == null) return null;

      // A stored zero, a negative, or a figure too large to invert is not a
      // rate — it is a bad row. Using it would quietly change the money, so it
      // is refused and the caller takes the "no rate" path, which is honest.
      final stored = (row['rate_e9'] as num).toInt();
      final rateE9 = direct != null ? stored : invertRateE9(stored);
      if (!isUsableRateE9(rateE9)) return null;

      return RateQuote(
        from: from,
        to: to,
        rateE9: rateE9!,
        asOf: (row['as_of'] as String?) ?? '',
        source: (row['source'] as String?) ?? 'cache',
        fetchedAt: DateTime.tryParse((row['fetched_at'] as String?) ?? '') ?? DateTime.now(),
        cached: true,
      );
    } catch (_) {
      // No session, no network, or the table is unreachable. The caller's next
      // step is the same either way.
      return null;
    }
  }

  Future<void> _store(String base, RateTable table) async {
    try {
      await _client.rpc('upsert_exchange_rates', params: {
        'p_base': base,
        'p_rates': table.rates,
        'p_as_of': table.asOf,
        'p_source': table.source,
      });
    } catch (_) {
      // Caching is an optimisation. Failing to cache must not fail the lookup
      // the user is waiting on.
    }
  }

  /// Null when both sources fail — including when one answers with something
  /// that is not a rate table at all. The shape rules live in
  /// `rate_source.dart`, where they are tested without a socket.
  Future<RateTable?> _fetch(String base) async {
    final primary = parsePrimaryRates(await _getJson('$kPrimaryRateUrl/$base'));
    if (primary != null) return primary;

    return parseFallbackRates(await _getJson('$kFallbackRateUrl?base=$base'));
  }

  Future<Map<String, dynamic>?> _getJson(String url) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _timeout;
      final request = await client.getUrl(Uri.parse(url)).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join().timeout(_timeout);
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      // Offline, DNS failure, timeout, malformed JSON: one answer for all of
      // them, which is "no rate from this source right now".
      return null;
    } finally {
      client?.close(force: true);
    }
  }

}

/// One rate, with enough provenance for the UI to be honest about it.
class RateQuote {
  const RateQuote({
    required this.from,
    required this.to,
    required this.rateE9,
    required this.asOf,
    required this.source,
    required this.fetchedAt,
    required this.cached,
  });

  factory RateQuote.identity(String currency) => RateQuote(
        from: currency,
        to: currency,
        rateE9: kRateScale,
        asOf: DateTime.now().toIso8601String().substring(0, 10),
        source: 'identity',
        fetchedAt: DateTime.now(),
        cached: false,
      );

  final String from;
  final String to;

  /// One [from] costs rateE9/1e9 [to].
  final int rateE9;
  final String asOf;
  final String source;
  final DateTime fetchedAt;
  final bool cached;

  bool isOlderThan(Duration age) => DateTime.now().difference(fetchedAt) > age;

  /// True when this came from the cache and is more than a day behind.
  bool get stale => cached && isOlderThan(const Duration(hours: 24));

  /// "1 AED = ₹24.01" — the line that stops a conversion being a mystery.
  String get sentence => rateSentence(from, to, rateE9);

  /// Where this number came from and how old it is, in words.
  String get provenance {
    if (source == 'identity') return 'Same currency';
    if (!cached) return 'Live rate · $source · $asOf';
    if (stale) return 'Cached rate from $asOf · offline';
    return 'Cached rate · $asOf';
  }
}
