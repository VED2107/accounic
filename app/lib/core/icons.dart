library;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The icon language (context.md §18).
///
/// One family — Lucide — at one stroke weight, addressed by what a glyph
/// *means* rather than by what it draws. Screens name the role (`AppIcons.
/// receivable`), never the picture, so the day a glyph is judged wrong it is
/// changed here and everywhere at once.
///
/// Direction glyphs follow `docs/accounting-direction.md` and are the same
/// arrows the web client uses:
///
///   receivable  ↗  money left the owner, and is owed back
///   payable     ↙  money arrived, and the owner owes it back
///   settlement  ↔  an exchange that retires an open amount
///
/// A direction is never carried by the arrow alone. Every place one of these
/// appears, a word and a colour appear with it (context.md §28) — an arrow is
/// an accelerator for a reader who already knows the rule, not the statement of
/// it.
abstract final class AppIcons {
  // ----------------------------------------------------------------- money
  static const IconData receivable = LucideIcons.arrowUpRight;
  static const IconData payable = LucideIcons.arrowDownLeft;
  static const IconData settlement = LucideIcons.arrowLeftRight;
  static const IconData net = LucideIcons.scale;
  static const IconData amount = LucideIcons.banknote;
  static const IconData transaction = LucideIcons.receipt;
  static const IconData trend = LucideIcons.trendingUp;

  // ------------------------------------------------------------ navigation
  static const IconData dashboard = LucideIcons.layoutDashboard;
  static const IconData people = LucideIcons.users;
  static const IconData activity = LucideIcons.activity;
  static const IconData profile = LucideIcons.user;
  static const IconData admin = LucideIcons.shield;
  static const IconData search = LucideIcons.search;

  // ---------------------------------------------------------------- action
  static const IconData add = LucideIcons.plus;
  static const IconData addPerson = LucideIcons.userPlus;
  static const IconData edit = LucideIcons.pencil;
  static const IconData archive = LucideIcons.archive;
  static const IconData delete = LucideIcons.trash2;
  static const IconData more = LucideIcons.ellipsisVertical;
  static const IconData forward = LucideIcons.chevronRight;
  static const IconData back = LucideIcons.arrowLeft;
  static const IconData close = LucideIcons.x;
  static const IconData refresh = LucideIcons.refreshCw;
  static const IconData signOut = LucideIcons.logOut;
  static const IconData expand = LucideIcons.chevronDown;

  // ---------------------------------------------------------------- status
  static const IconData check = LucideIcons.check;
  static const IconData success = LucideIcons.circleCheck;
  static const IconData warning = LucideIcons.circleAlert;
  static const IconData locked = LucideIcons.lock;
  static const IconData reveal = LucideIcons.eye;
  static const IconData conceal = LucideIcons.eyeOff;

  // ----------------------------------------------------------------- forms
  static const IconData person = LucideIcons.user;
  static const IconData business = LucideIcons.building2;
  static const IconData phone = LucideIcons.phone;
  static const IconData email = LucideIcons.mail;
  static const IconData address = LucideIcons.mapPin;
  static const IconData currency = LucideIcons.coins;
  static const IconData date = LucideIcons.calendar;
  static const IconData note = LucideIcons.fileText;

  // ------------------------------------------------------------ empty sets
  static const IconData noPeople = LucideIcons.users;
  static const IconData noResults = LucideIcons.searchX;
  static const IconData noFilterMatch = LucideIcons.filterX;
  static const IconData quiet = LucideIcons.inbox;
}

/// Optical sizes. Lucide is drawn on a 24px grid with a 2px stroke; rendered
/// below about 16px that stroke thickens visually, so the small sizes here are
/// the ones that still read cleanly rather than an arbitrary ramp.
abstract final class AppIconSize {
  /// Inside a chip or beside caption text.
  static const double xs = 14;

  /// Inside a row, a button, a field prefix — the default.
  static const double sm = 16;

  /// Navigation, section headers.
  static const double md = 18;

  /// A tile's leading badge.
  static const double lg = 20;

  /// An empty state's mark.
  static const double xl = 24;
}
