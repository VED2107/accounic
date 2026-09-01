library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'statement_pdf.dart';

/// Where a saved statement ended up, or why it did not.
///
/// A sealed result rather than an exception for the ordinary outcomes: the user
/// cancelling a save dialog is not an error, and a screen that reports it as
/// one is lying to them. Only the genuinely unexpected throws.
sealed class StatementSaveResult {
  const StatementSaveResult();
}

/// Saved. [path] is the file the user can now open.
class StatementSaved extends StatementSaveResult {
  const StatementSaved(this.path, {required this.chosen});

  final String path;

  /// True when the user picked the location, false when it went to the
  /// platform's downloads folder because there was no dialog to show.
  final bool chosen;
}

/// The user closed the save dialog. Nothing was written, and nothing is wrong.
class StatementSaveCancelled extends StatementSaveResult {
  const StatementSaveCancelled();
}

/// Something went wrong that the user needs told about, in their words.
class StatementSaveFailed extends StatementSaveResult {
  const StatementSaveFailed(this.message);

  final String message;
}

/// Builds a person's statement and puts the file where the user can reach it.
///
/// Two behaviours, because the two platforms genuinely differ:
///
///   * **Windows** (and any desktop) opens a native save dialog, defaulting to
///     the Downloads folder with a sensible filename. Cancelling it is a
///     first-class outcome, not an error.
///   * **Android** has no save dialog worth showing for this, so the file goes
///     to the app's external files directory — reachable from a file manager,
///     needing no storage permission on any supported Android version — and
///     falls back to the app documents directory when there is no external
///     storage at all.
///
/// Every failure below is caught and turned into a sentence: an unwritable
/// directory, a file locked by another program, a disk that is full. None of
/// them crash the app, and none of them leave a half-written PDF behind that
/// the user might open.
class StatementDownloader {
  const StatementDownloader();

  /// True on the platforms that have a native save dialog worth showing.
  static bool get _hasSaveDialog =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<StatementSaveResult> save({
    required PersonPage page,
    required String ownerName,
  }) async {
    final Uint8List bytes;
    try {
      bytes = await PersonStatement.build(page: page, ownerName: ownerName);
    } catch (_) {
      return const StatementSaveFailed(
        'The statement could not be prepared. Nothing has been saved.',
      );
    }

    // A PDF that is not a PDF is worse than no PDF: it opens to an error in
    // whatever the user's reader is, and looks like our fault twice.
    if (bytes.lengthInBytes < 5 ||
        bytes[0] != 0x25 || // %
        bytes[1] != 0x50 || // P
        bytes[2] != 0x44 || // D
        bytes[3] != 0x46) {
      return const StatementSaveFailed(
        'The statement came back unreadable and was not saved.',
      );
    }

    final name = fileName(page.person.name);

    if (_hasSaveDialog) {
      final FileSaveLocation? location;
      try {
        location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'PDF', extensions: ['pdf'], mimeTypes: ['application/pdf']),
          ],
        );
      } catch (_) {
        // No dialog available — fall through to the downloads folder rather
        // than telling the user their statement cannot be saved at all.
        return _writeToDownloads(bytes, name);
      }

      if (location == null) return const StatementSaveCancelled();
      return _write(bytes, _withPdfExtension(location.path), chosen: true);
    }

    return _writeToDownloads(bytes, name);
  }

  /// Puts any already-built export where the user can reach it.
  ///
  /// The same two behaviours as [save] — a native dialog on desktop, the
  /// external files directory on Android — for a file this class did not build
  /// itself. The workspace export (PDF, CSV, JSON) comes through here, so there
  /// is one save path in the app rather than one per format.
  Future<StatementSaveResult> saveBytes({
    required Uint8List bytes,
    required String filename,
    required String typeLabel,
    required String extension,
    required String mimeType,
  }) async {
    if (bytes.isEmpty) {
      return StatementSaveFailed('The $typeLabel came back empty and was not saved.');
    }

    if (_hasSaveDialog) {
      final FileSaveLocation? location;
      try {
        location = await getSaveLocation(
          suggestedName: filename,
          acceptedTypeGroups: [
            XTypeGroup(
              label: typeLabel,
              extensions: [extension],
              mimeTypes: [mimeType],
            ),
          ],
        );
      } catch (_) {
        return _writeToDownloads(bytes, filename);
      }

      if (location == null) return const StatementSaveCancelled();
      final path = location.path.toLowerCase().endsWith('.$extension')
          ? location.path
          : '${location.path}.$extension';
      return _write(bytes, path, chosen: true);
    }

    return _writeToDownloads(bytes, filename);
  }

  Future<StatementSaveResult> _writeToDownloads(Uint8List bytes, String name) async {
    Directory? directory;
    try {
      directory = Platform.isAndroid
          ? (await getExternalStorageDirectory() ??
              await getApplicationDocumentsDirectory())
          : (await getDownloadsDirectory() ??
              await getApplicationDocumentsDirectory());
    } catch (_) {
      return const StatementSaveFailed(
        'There is nowhere to save the statement on this device.',
      );
    }

    return _write(bytes, '${directory.path}${Platform.pathSeparator}$name', chosen: false);
  }

  Future<StatementSaveResult> _write(
    Uint8List bytes,
    String path, {
    required bool chosen,
  }) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return StatementSaved(path, chosen: chosen);
    } on PathAccessException {
      return const StatementSaveFailed(
        'That location could not be written to. Try saving somewhere else.',
      );
    } on FileSystemException catch (error) {
      // The message the OS gives is usually the useful part — "the process
      // cannot access the file because it is being used by another process" is
      // exactly what a user with the PDF already open needs to read.
      final detail = error.osError?.message.trim();
      return StatementSaveFailed(
        detail == null || detail.isEmpty
            ? 'The statement could not be written to disk.'
            : 'The statement could not be saved: $detail',
      );
    } catch (_) {
      return const StatementSaveFailed('The statement could not be saved.');
    }
  }

  static String _withPdfExtension(String path) =>
      path.toLowerCase().endsWith('.pdf') ? path : '$path.pdf';

  /// A filename that is safe on every platform and still recognisable. The same
  /// rule the web route's `slug()` applies, so a statement saved from either
  /// client arrives with the same name.
  static String fileName(String personName) {
    final cleaned = personName
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-')
        .toLowerCase();
    return '${cleaned.isEmpty ? 'account' : cleaned}-statement.pdf';
  }
}
