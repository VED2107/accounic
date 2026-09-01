import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/failure.dart';
import 'export_models.dart';

/// Fetching an export (milestone 1.9.0, Phases 4–6).
///
/// Two RPCs and a loop, exactly as on the web: `export_workspace()` is one
/// round trip, and the ledger is paged, because a workspace with fifty thousand
/// entries must not become one request that times out on a phone.
///
/// Nothing here filters, sorts or computes. The database applies the filter
/// contract and returns entries in a deterministic order; this walks the pages
/// until it has them, and says so when it stops early rather than quietly
/// handing back a partial backup.
class ExportRepository {
  ExportRepository(this._client);

  final SupabaseClient _client;

  /// The most entries one export will assemble in memory on a phone.
  static const int maxEntries = 20000;

  /// The page size asked of `export_entries()`; its own cap is 5,000.
  static const int pageSize = 1000;

  Future<ExportHeader> header(ExportFilters filters) async {
    try {
      final data = await _client.rpc('export_workspace', params: filters.toParams());
      return ExportHeader.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(error, 'Your export could not be prepared.', stack);
    }
  }

  Future<ExportEntryPage> page(
    ExportFilters filters, {
    int offset = 0,
    int limit = pageSize,
  }) async {
    try {
      final data = await _client.rpc(
        'export_entries',
        params: {...filters.toParams(), 'p_limit': limit, 'p_offset': offset},
      );
      return ExportEntryPage.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(error, 'Your export could not be read.', stack);
    }
  }

  /// The header and every entry it describes.
  ///
  /// [onProgress] is called with (loaded, total) after each page, so a sheet can
  /// show real progress on a large workspace instead of an indeterminate
  /// spinner that says nothing.
  Future<ExportBundle> load(
    ExportFilters filters, {
    void Function(int loaded, int total)? onProgress,
  }) async {
    final head = await header(filters);
    final entries = <ExportEntry>[];
    var truncated = false;
    var offset = 0;

    while (true) {
      final result = await page(filters, offset: offset);
      entries.addAll(result.entries);
      onProgress?.call(entries.length, result.total);

      if (!result.hasMore) break;
      if (entries.length >= maxEntries) {
        truncated = true;
        break;
      }
      offset += result.limit;
    }

    return ExportBundle(header: head, entries: entries, truncated: truncated);
  }
}
