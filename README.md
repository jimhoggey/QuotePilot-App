# Quote Pilot

A simple Mac app for the paperwork side of a one-person business: send a quote, let the client tick
the lines they want right on the PDF, invoice for what they accepted, and see at a glance what's been
paid and what's still owed.

**Status:** in progress. The business rules and the PDFs are built and tested. The Mac app's screens
come next.

## What works today

- **Quote PDFs the client can tick.** Every line has an ID and a tick box, with an "Accept all" box at
  the top and fields for the client's name and the date. The form is a standard PDF form (an AcroForm),
  so PDF apps that fill in forms can tick it; so far it's been tested in Apple's Preview and in pdf.js.
- **Reading a returned quote.** The ticks, name and date come back out of the PDF and become a
  proposal: which lines were accepted, which were declined, and anything that needs a second look.
- **Invoicing rules.** A payment plan per quote: **50/50** (a deposit invoice, then the balance on
  completion) or **full amount**. Only accepted lines are billed, and the deposit and balance always
  add up to the accepted total exactly.
- **Payments and figures.** Payments, overdue invoices, money received this month and this
  financial year (1 July to 30 June), and a spreadsheet of payments for tax time.
- **Safe storage.** One library file, saved atomically, never overwritten if it can't be read, with
  dated backups and restore.
- **Import** from the earlier single-page Invoice Generator.
- **`qp`,** a small command-line tool for trying the PDFs before the app exists.

## Coming next: the Mac app

The screens: a dashboard, quote and invoice editors with a live PDF preview, dropping a returned quote
onto the window, ticking lines by hand when a client can't fill the form, recording payments, your
logo and font, and Mail drafts with the PDF attached (you always press Send yourself). Everything
will stay on your Mac.

## Building

Needs macOS 14 or later and Apple's Command Line Tools (Xcode isn't required).

```bash
swift build
swift test
swift run qp samples build/samples     # sample quote, invoices and receipt
swift run qp read "build/samples/Q-0001 Sample Client Pty Ltd.pdf"
```

## Licence

MIT. See `LICENSE`.
