# Invoice Templates

The user, 5 Nov 2026: templates for invoices only, made in a form in Brand → Documents. Example: a
template titled "Billing for meeting time" with one line, "Meeting time", 1 hour. They worry the app is
getting complex, so keep it as small as possible:

- Nothing new shows until a template exists.
- Templates add one control: the New Invoice menu.
- No separate template name. The template's title is what the menu shows and what the new invoice's
  Reference becomes.

**The rule above everything else** (the user): Quote Pilot's biggest selling point is that it's easy
to navigate and easy to understand while still feature-rich, and every button must make sense.

Before merging, look at the snapshots as a first-time user would:
- Can you tell what each button does from its label alone?
- Is there one obvious way to start an invoice from a template?
- Would someone with no templates notice any change? They shouldn't.

If the Documents tab gets crowded, simplify. Don't squeeze.

One branch (`feature/invoice-templates`), one feature commit, a PR, then version 1.9.0 and a release.

## Model (QuotePilotCore)

- `InvoiceTemplate: Codable, Hashable, Identifiable, Sendable`:
  - `id: UUID`;
  - `title: String`, the Reference of invoices made from it and its name in the menu;
  - `lines: [LineItem]`.
- `Brand.invoiceTemplates: [InvoiceTemplate] = []`:
  - decode it with `c.value(.invoiceTemplates, or: [])`;
  - add it to `Brand.CodingKeys`.
- `Library.newInvoice(on:clientID:from template: InvoiceTemplate? = nil)`. With a template:
  - the title is the template's title;
  - the lines are `template.lines.map(\.freshCopy)`;
  - the rest is as now (due date, GST, terms from Brand).
- Add `Library.problems()` checks for template lines, as for invoice lines (amount and quantity limits).
  Use the existing `check(lines, of:)` and name each template by its title.

## Using a template (QuotePilotUI)

- `AppModel.newInvoice(for:from:)` passes the template through.
- **New Invoice** in the toolbar (`RootView.swift:143`):
  - no templates: unchanged;
  - with templates: a menu of "Blank Invoice" plus each template's title, in the order of the Brand list. Check the Win95 look of a `Menu` in the toolbar; match the other toolbar buttons.
- **File menu** (`Commands.swift:23`): "New Invoice" stays as it is (⇧⌘N, blank). With templates, add a
  "New Invoice from Template" submenu after it. Same label everywhere.

## The form (Brand → Documents, `DocumentsTab` in `BrandView.swift`)

A GroupBox **Invoice templates** after Invoices:

- **New Template**: adds an empty template and selects it.
- **Delete Template**: removes the selected one. No question; it's a starting point, not a document.
  Greyed out with none selected.
- A list of the templates by title.
- The selected template's form:
  - **Title** (`Win95TextField`);
  - its lines in `LinesEditor` (`showCodes: false`, `showDecision: false`, `editable: true`, `done: nil`, `onAdd` appends `LineItem()`).
- A one-line note: "Start one with the arrow on New Invoice in the toolbar."
- Brand edits save as you type through `brandBinding`, as the other Brand fields do.
- **Width risk:** the Documents tab shares the window with the sample preview.
  - Check `LinesEditor` fits the tab at the smallest window (980 × 620; 778 beside the tree) with a snapshot test `brand-documents-templates`.
  - If it doesn't fit, give the template lines a compact editor: title, quantity, unit and rate in one row.

## Tests

- **Core:**
  - a template's invoice has its title and fresh copies of its lines (new ids), and Brand's due date and terms;
  - older libraries have no templates;
  - an out-of-range template line is a problem.
- **UI:**
  - `newInvoice(from:)` opens the new invoice with the template's line;
  - the snapshot above;
  - the New Invoice menu only offers templates when some exist (test the list the menu is built from).

## Release

- WhatsNew 1.9.0: "Invoice templates: set one up in Brand → Documents, then start an invoice from it with New Invoice in the toolbar."
- README: a line under Invoices.
- CLAUDE.md history.
- `./scripts/release.sh 1.9.0`.
