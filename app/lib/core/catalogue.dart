library;

/// What Accounic actually does, group by group (docs/demo.md).
///
/// The demo screen renders this, and it exists for one reason: a visitor
/// exploring a restricted surface will otherwise conclude that the restricted
/// surface is the product. It is not. This is the inventory of the real thing,
/// with the demo's own share of it marked honestly — including the parts the
/// demo does have, because a list where nothing is ticked reads as a paywall
/// rather than as a product.
///
/// ---------------------------------------------------------------------------
/// THE RULE FOR THIS FILE: it describes what is BUILT, never what is planned.
///
/// Every line below is a capability that exists in this repository today, and
/// most can be followed to the migration or the file that implements it. A
/// marketing list is allowed to describe an ambition; a list the product shows
/// to a customer inside the product is a promise, and a promise the software
/// does not keep is the one thing a demo must never do.
/// ---------------------------------------------------------------------------
class Capability {
  const Capability(this.label, {this.inDemo = false, this.detail});

  /// The capability, named as a user would name it.
  final String label;

  /// Whether the visitor can reach it in the demo right now.
  final bool inDemo;

  /// One clause of substance, where the label alone would be a slogan. Left
  /// null far more often than it is set: a list of forty explained lines is a
  /// document, not a list.
  final String? detail;
}

class CapabilityGroup {
  const CapabilityGroup(this.title, this.capabilities, {this.note});

  final String title;

  /// What this group is FOR, in one line, so the group reads as an answer to a
  /// question rather than as a heading over a pile.
  final String? note;

  final List<Capability> capabilities;

  int get demoCount => capabilities.where((c) => c.inDemo).length;
}

/// The whole product.
const kAccounicCapabilities = <CapabilityGroup>[
  CapabilityGroup(
    'Dashboard',
    note: 'Where you stand, before you have asked anything.',
    [
      Capability('Total receivable', inDemo: true),
      Capability('Total payable', inDemo: true),
      Capability('Net balance', inDemo: true),
      Capability('People count and transaction overview', inDemo: true),
      Capability('Recent activity', inDemo: true),
      Capability('Thirty-day trend', inDemo: true),
      Capability(
        'Cash in hand',
        inDemo: true,
        detail: 'The regular trading position, kept apart from opening balances',
      ),
      Capability('Settlement summary', inDemo: true),
      Capability('Opening balance summary'),
      Capability('Currency-wise breakdown'),
    ],
  ),

  CapabilityGroup(
    'People and accounts',
    note: 'One account per person or business, and its whole history.',
    [
      Capability('Add, edit and delete people', inDemo: true),
      Capability('Individual account view', inDemo: true),
      Capability('Per-person balance', inDemo: true),
      Capability('Credit and debit history', inDemo: true),
      Capability('Overview, transactions, settlements and activity tabs', inDemo: true),
      Capability('People and businesses as distinct account types', inDemo: true),
      Capability('Search across people and transactions', inDemo: true),
      Capability('Sort by name, balance or recent activity', inDemo: true),
      Capability('Archive and restore an account'),
      Capability('Per-account currency'),
      Capability('Opening balance'),
      Capability(
        'Retract an account’s whole history',
        detail: 'Voided, not deleted: every row keeps its amount and its date',
      ),
    ],
  ),

  CapabilityGroup(
    'Transactions',
    note: 'What was lent, what was borrowed, and when.',
    [
      Capability('Credit transactions', inDemo: true),
      Capability('Debit transactions', inDemo: true),
      Capability('Transaction history and details', inDemo: true),
      Capability('Date-based entries with a shared calendar', inDemo: true),
      Capability('Notes and descriptions', inDemo: true),
      Capability('Edit a recorded transaction', inDemo: true),
      Capability(
        'Void a transaction',
        inDemo: true,
        detail: 'A retraction that stays visible, never a deletion',
      ),
      Capability('Original transaction currency preserved'),
      Capability('Historical exchange rate preserved'),
      Capability(
        'Transfers between two people',
        detail: 'One record, two linked entries, retracted together or not at all',
      ),
      Capability('Idempotent transfers', detail: 'A double tap cannot move money twice'),
    ],
  ),

  CapabilityGroup(
    'Settlements',
    note: 'Money that actually changed hands.',
    [
      Capability('Record money paid or received', inDemo: true),
      Capability('Settlement in and settlement out', inDemo: true),
      Capability('Partial settlements', inDemo: true),
      Capability('Outstanding balance tracking', inDemo: true),
      Capability('Original transactions remain intact', inDemo: true),
      Capability('Reverse a settlement', inDemo: true),
      Capability('FIFO settlement allocation', detail: 'Oldest debts close first'),
      Capability('Targeted settlement priority', detail: 'Settle a chosen entry'),
      Capability('Settlement scope, separating opening from regular books'),
      Capability('Settle an opening balance on its own'),
    ],
  ),

  CapabilityGroup(
    'Multi-currency',
    note: 'An account kept in one currency, paid in another, and honest about both.',
    [
      Capability('Figures in your workspace currency', inDemo: true),
      Capability('Per-person account currencies'),
      Capability('Multiple currencies across accounts'),
      Capability('Live exchange rates'),
      Capability('Cached exchange rates'),
      Capability('Automatic currency conversion'),
      Capability(
        'Manual rate and manual amount override',
        detail: 'What actually arrived, when a bank disagrees with the rate',
      ),
      Capability('Original amount, currency and rate preserved on every row'),
      Capability('Currency-wise dashboard breakdown'),
      Capability('INR-first currency ordering'),
    ],
  ),

  CapabilityGroup(
    'Activity',
    note: 'Everything that happened, in the order it happened.',
    [
      Capability('Complete activity journal', inDemo: true),
      Capability('Day-by-day grouping', inDemo: true),
      Capability('Transaction and settlement events', inDemo: true),
      Capability('Filter by kind', inDemo: true),
      Capability('Thirty-day summary chart', inDemo: true),
      Capability('Export the journal as a document'),
    ],
  ),

  CapabilityGroup(
    'Reports and exports',
    note: 'Your books as a document you can send to someone.',
    [
      Capability('Workspace ledger PDF'),
      Capability('Per-account statement PDF'),
      Capability('Activity journal PDF'),
      Capability('Spreadsheet (CSV) export'),
      Capability('Full JSON backup'),
      Capability('Filtered exports by date, account and kind'),
      Capability('A preview of what an export will contain, before it is made'),
    ],
  ),

  CapabilityGroup(
    'Security and isolation',
    note: 'Enforced by the database, not by the interface.',
    [
      Capability('Row Level Security on every table', inDemo: true),
      Capability('Multi-tenant data isolation', inDemo: true),
      Capability(
        'Cross-tenant access prevention',
        inDemo: true,
        detail: 'An administrator cannot read another user’s ledger either',
      ),
      Capability('Validated writes through RPCs only', inDemo: true),
      Capability('Rate limiting on every write path', inDemo: true),
      Capability('Sanitised client error reporting', inDemo: true),
      Capability('User authentication'),
      Capability('Role-based administration'),
      Capability('Disabled-account protection'),
      Capability('Service-role access kept server-side'),
    ],
  ),

  CapabilityGroup(
    'Administration',
    note: 'Managing who may sign in — never what they can see.',
    [
      Capability('Admin dashboard and system counters'),
      Capability('User and account directory'),
      Capability('Create a user, reset a password'),
      Capability('Enable and disable an account'),
      Capability('Grant and revoke administrator access'),
      Capability('Demo users, listed and convertible to real users'),
      Capability('An administrative audit of what was changed, and by whom'),
    ],
  ),

  CapabilityGroup(
    'The accounting engine',
    note: 'The part that is the same for everyone, including this demo.',
    [
      Capability('Database-driven balance calculation', inDemo: true),
      Capability(
        'Integer minor units',
        inDemo: true,
        detail: 'No floating point ever touches money',
      ),
      Capability('Currency-specific decimal precision', inDemo: true),
      Capability('Accounting rules held in the database', inDemo: true),
      Capability('One engine for every client', inDemo: true),
      Capability('Opening balance and transfer handling'),
    ],
  ),

  CapabilityGroup(
    'Applications',
    note: 'Three clients, one backend, one database.',
    [
      Capability('Web application', inDemo: true),
      Capability('Responsive from phone to desktop', inDemo: true),
      Capability('Dark and light interface', inDemo: true),
      Capability('Custom date picker, shared by every form', inDemo: true),
      Capability('Keyboard-aware forms and reduced-motion support', inDemo: true),
      Capability('Real URLs, deep links and platform back behaviour', inDemo: true),
      Capability('Android application'),
      Capability('Windows desktop application'),
      Capability('Windows installer and portable build'),
      Capability('In-app update checking against published releases'),
    ],
  ),
];

/// How many capabilities the demo actually opens, and how many exist.
///
/// Computed rather than written down, so the two numbers cannot drift from the
/// list above them — which is exactly the failure mode of every feature table
/// that has ever been maintained by hand.
int get kCapabilityTotal =>
    kAccounicCapabilities.fold(0, (sum, group) => sum + group.capabilities.length);

int get kCapabilityInDemo =>
    kAccounicCapabilities.fold(0, (sum, group) => sum + group.demoCount);
