library;

import 'config.dart';

/// Demo mode (docs/demo.md).
///
/// There is no second application, no second data layer, no second accounting
/// engine and — since the demo moved into the real project — no second
/// database either. There is a build flag, an account flag, the surfaces that
/// consult them, and RLS doing exactly what it already did.
///
/// The rule the rest of the code follows: **demo mode restricts what is
/// reachable, never how anything is computed.** Every figure the visitor sees
/// came out of `create_transaction()`, `create_settlement()` and `dashboard()`.
/// Nothing in this file participates in arithmetic, and nothing in it may ever
/// be given a number to work out.
///
/// ---------------------------------------------------------------------------
/// TWO FLAGS. THEY ARE NOT THE SAME FLAG.
///
///   [isDemoBuild]  — is this DEPLOYMENT the online demo?
///                    Compile-time, from --dart-define=DEMO_MODE=on. It decides
///                    which door the visitor arrives at: anonymous sign-in
///                    instead of a login form.
///
///   `me.isDemo`    — is this ACCOUNT a demo account?
///                    Runtime, from `profiles.is_demo` by way of `me()`. It
///                    decides whether this person's experience is restricted,
///                    and it travels with them: the demo account signing in to
///                    the Windows build is still a demo account there.
///
/// Collapsing the two would get both wrong. An administrator opening the demo
/// build is not a demo user, and a demo account on a production build is not a
/// full customer. `demoRestrictedProvider` in providers.dart is the OR of the
/// two, and is what every gate actually asks.
/// ---------------------------------------------------------------------------
bool get isDemoBuild => AppConfig.demoMode;

/// The capabilities a demo does not open.
///
/// Each one exists in this binary, works, and is reached by the same code path
/// a paying user reaches it by. What the demo changes is whether the button
/// leads there or to [DemoFeature.blurb].
enum DemoFeature {
  reports(
    'Reports and exports',
    'Your books as a PDF report, a spreadsheet, or a full backup — for one '
        'account or for the whole workspace.',
  ),

  transfers(
    'Transfers',
    'Move money between two people as one record, with both sides written '
        'together and retracted together.',
  ),

  settlementAllocation(
    'Settlement allocation',
    'Settle a specific transaction rather than the balance, and decide what a '
        'part payment pays off first.',
  ),

  multiCurrency(
    'Multi-currency accounting',
    'Keep each account in its own currency, enter a payment in another, and '
        'record the rate that was used at the moment it was used.',
  ),

  openingBalance(
    'Opening balances',
    'Start an account from what was already owed, then adjust and settle that '
        'opening figure on its own books.',
  ),

  administration(
    'Administration',
    'Create the people who can sign in, and decide who keeps access.',
  ),

  account(
    'Your own workspace',
    'A private ledger that is yours — your currency, your password, your data, '
        'on your phone and your desktop at once.',
  );

  const DemoFeature(this.title, this.blurb);

  /// What the capability is called, in the product's own words.
  final String title;

  /// One sentence on what it does. Not a feature list — a reason.
  final String blurb;
}

/// What the full application adds, as the upgrade sheet lists it.
///
/// Kept here rather than in the widget so the demo-versus-full screen and the
/// gate sheet cannot drift apart and promise different products.
const kFullAccounicPromises = <String>[
  'Advanced settlement, including part payments against a chosen transaction',
  'Full multi-currency accounting with recorded exchange rates',
  'Opening balances, adjustments and transfers between accounts',
  'PDF statements, workspace exports and the activity journal',
  'Your own private books, kept for as long as you keep them',
];

/// How full access is actually obtained, in one sentence.
///
/// This is the whole flow, and the demo says it everywhere rather than implying
/// a download: an administrator enables the account, and the account is the one
/// the visitor is already signed in to.
const String kAccessGrantedBy =
    'Full access is enabled by an administrator, on the account you are already '
    'signed in to. Nothing is re-created and nothing is copied — your books stay '
    'exactly as you left them.';

/// Where the full application is downloaded from, ONCE an account has been
/// enabled (`--dart-define=FULL_APP_URL=…`, core/config.dart).
///
/// Deliberately not a call to action for a demo visitor. It is what an
/// administrator hands over after converting someone, which is why the only
/// screen that offers it is the administrator's own confirmation.
String get kFullAccounicUrl => AppConfig.fullAppUrl;

/// What a demo visitor is actually asked to do, in the demo's own words.
///
/// Deliberately NOT a link, and deliberately not a mail client.
///
/// Opening the visitor's email app is the wrong move twice over. It throws them
/// out of the product mid-evaluation into an application that may not be
/// configured, on a device that may have no mail account at all — and it dresses
/// an administrative decision up as a purchase form. The honest thing is to say
/// who grants access and let them go and ask.
const String kHowToGetFullAccess =
    'Ask your Accounic administrator to enable full access for this account. '
    'They do it from Administration in a couple of clicks, and you carry on in '
    'the same account with the same books.';
