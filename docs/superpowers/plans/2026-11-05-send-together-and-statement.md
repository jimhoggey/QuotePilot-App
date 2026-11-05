# Send Together and Statements

Two changes the user asked for on 5 Nov 2026, each on its own branch from main, its own commit and
PR. Research behind them: bundling several invoices for one client into one email is fine as long as
each invoice stays its own PDF with its own number; a statement lists what a client owes with the
total, and never replaces the tax invoices.

## 1. Send Together (branch `feature/send-together`)

The user: select both draft invoices in the Dashboard's "Drafts not sent yet" list, right-click,
Send Together.

- **Multi-select in `DetailsList`** (`Sources/QuotePilotUI/Win95/DetailsList.swift`): an optional
  `multiSelection: Binding<Set<ID>>? = nil`. Lists that don't pass it behave as now.
  - Plain click and the arrow keys select one row: the set holds that row alone.
  - ⌘-click adds or removes a row. ⇧-click selects the range from `selection`, which is the anchor.
  - A right-click on a row already in the set keeps the set. On any other row it selects that row alone.
  - Highlight rows in the set.
  - Put the rule in a pure `DetailsLayout` function, read the modifiers from `NSEvent.modifierFlags`, and test it.
- **Dashboard** (`DashboardView.swift`): the Drafts list passes `@State selectedDrafts`. Its row menu:
  - **Open**, the same as a double-click.
  - **Send Together**, greyed out unless 2+ rows are selected, all are invoices, all have one client, and nothing is locked.
- **Mail**:
  - `MailDocument` gets `case invoices([UUID])`.
  - `MailComposer.compose` takes `attachments: [URL]`. `NSSharingService` takes several `NSURL` items.
  - `send` writes each PDF to the sent folder. One "Did You Send It?" box: Yes marks every invoice sent.
  - Activity gets a line per invoice. Usage gets `track(.sent, ["kind": "invoices", "count": n])`.
- **Email wording**:
  - `EmailTemplates` gets `together`. Decode it with a default, so older libraries still open.
  - Placeholders: `{contact}`, `{count}`, `{list}` (one "• INV-0004, title, $750.00" line per invoice), `{amount}` (the total), `{due}` (the latest due date), `{business}`.
  - The body ends: "You're welcome to pay them in one transfer; please put the invoice numbers in the reference."
  - Brand → Emails gets "Invoices together email".
- **Tests**:
  - Core: the draft's wording and total.
  - UI: Send Together with `FakeMail` records every attachment and marks every invoice sent. Not Yet changes nothing.
  - The multi-select rule.

## 2. Statement (branch `feature/statement`)

- **Core**: `Library.statement(forClient:on:)` lists the client's sent, not fully paid invoices:
  - each one's number, issued date, due date, total, amount paid and amount owing, oldest first;
  - the total owing, and which invoices are overdue.
- **PDF**: `DocumentContent.statement` is drawn like an invoice:
  - the brand header, the title "Statement", the client and the date;
  - the table, the total owing, and the brand's payment details;
  - a line saying each invoice is its own tax invoice.
- **Mail**:
  - `MailDocument.statement(clientID)`, with an `EmailTemplates.statement` template using `{contact}`, `{count}`, `{amount}` and `{business}`.
  - Brand → Emails gets "Statement email".
  - Nothing is marked sent. Activity gets a line.
- **UI**: Clients gets one **Send Statement** button for the selected client. It's greyed out when nothing is owing.
- **Tests**: what the statement holds (part-paid, overdue, void, and draft left out), the PDF draws, and the mail draft.

## Then

Version 1.8.0, with a WhatsNew entry naming:
- the custom split (already on `feature/payment-split`);
- Send Together;
- statements.

Then `./scripts/release.sh 1.8.0`.
