# Quote Pilot

A simple Mac app for the paperwork side of a one-person business: send a quote, let the client tick
the lines they want right on the PDF, invoice for what they accepted, and see at a glance what's been
paid and what's still owed.

**Status:** in progress. The business rules, the PDFs and the first half of the Mac app are built and
tested. Mail drafts, reading returned quotes, invoicing, payments and backups on screen come next.

## Built and tested so far

The engine the app will run on is written and covered by automated tests. Today you can try the quote, invoice and receipt PDFs with the `qp` tool; everything else runs once the app's screens arrive.

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
- **Import** of documents from the earlier single-page Invoice Generator.
- **`qp`,** a small command-line tool for trying the PDFs before the app exists.

## The Mac app

A Windows 95-style window: a navy title bar, bevelled buttons and pixel icons, built to be read at a
glance.

- **Dashboard:** what you're waiting to be paid, what's overdue, what's come in this financial year
  and what's quoted, in big numbers, with the lists behind them.
- **Quotes:** a list, and an editor with a live preview of the PDF the client will tick.
- **Clients**, **Brand** (logo, heading font, colour, wording and terms) and **Activity**, a log of
  every change.
- **Invoices** can be listed and saved as PDFs. Drafting, sending and payments come next.
- Every change saves as you make it, with a daily backup. If the library file is ever damaged,
  Quote Pilot won't save over it and offers the latest backup instead.

## Coming next

Mail drafts with the PDF attached (you always press Send yourself), dropping a returned quote onto the
window, ticking lines by hand, the invoice editor, payments and receipts, import from the old
Invoice Generator, and backup and restore on screen.

## Building

Needs macOS 14 or later and Apple's Command Line Tools (Xcode isn't required).

`swift build` builds the libraries (`QuotePilotCore` for the rules, `QuotePilotPDF` for the PDFs and
`QuotePilotUI` for the screens), the app and the `qp` tool. `swift test` runs the tests, and
`./build.sh` makes `build/Quote Pilot.app`.

Command Line Tools 27.0 ship the macOS 27 SDK without SwiftUI's macro plugin, which only comes with
Xcode. Without Xcode, build against the macOS 26.5 SDK the tools also include. `build.sh` does this
itself; for the other commands, run this first:

```bash
export SDKROOT="$(xcrun --sdk macosx26.5 --show-sdk-path)"
```

```bash
swift build
swift test
./build.sh                              # build/Quote Pilot.app
swift run qp samples build/samples      # sample quote, invoices and receipt
swift run qp read "build/samples/Q-0001 Sample Client Pty Ltd.pdf"
```

To try the app with a made-up business instead of your own library:

```bash
swift run qp demo /tmp/quote-pilot-demo
QP_LIBRARY_FOLDER=/tmp/quote-pilot-demo "build/Quote Pilot.app/Contents/MacOS/Quote Pilot"
```

Your real library lives in `~/Library/Application Support/Quote Pilot`, with daily backups in its
`Backups` folder.

## Licence

MIT. See `LICENSE`.
