# Quote Pilot

A simple Mac app for the paperwork side of a one-person business: send a quote, let the client tick
the lines they want right on the PDF, invoice for what they accepted, and see at a glance what's been
paid and what's still owed.

**Status:** the whole first version works. It covers quotes with a tick-box PDF, reading the
returned PDF, invoices (deposit and balance, or full amount), payments, receipts, Mail drafts, a
dashboard, and backups. It's built and tested on macOS 26 with Apple's Command Line Tools.

## Built and tested so far

The engine the app runs on is written and covered by automated tests. Everything below runs in the Mac app; the `qp` tool can also make sample PDFs and read a returned quote from the terminal.

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
- **`qp`,** a small command-line tool for trying the PDFs and a sample library from the terminal.

## The Mac app

A Windows 95-style window: a navy title bar, bevelled buttons and pixel icons, built to be read at a
glance.

**One button per action:** on any one screen an action has exactly one control, with the same label
everywhere ("Open Q-0001", naming the document). The step bar's button is that control while it
shows; with View → Show Steps off, the screen's own button takes its place.

- **Dashboard:** what you're waiting to be paid, what's overdue, what's come in this financial year
  and what's quoted, in big numbers, with the lists behind them.
- **Quotes:** an editor with a live preview of the PDF the client will tick. Quote Pilot never sends
  email itself. **Send by Mail** opens a Mail draft with the PDF attached; you press Send in Mail,
  then Quote Pilot asks "Did you send it?".
- **Returned quotes:** drop the client's PDF anywhere on the window, or use Read Reply (the
  toolbar, or File → Read Reply…). Check the ticks and confirm. A 50/50 quote then drafts its deposit invoice. If the
  client's app lost the ticks, tick the lines by hand.
- **Invoices:** deposits and balances from quotes (**Draft Invoice Now**, **Job Complete**), one-off
  invoices, payments, receipts, and voiding. Payments are entered in the invoice screen, with no
  dialog.
- **Clients**, **Brand** (logo, heading font, colour, wording and terms) and **Activity**, a log of
  what happened: quotes started and sent, Mail drafts, acceptances, invoices, payments and restores.
  ⌘F finds in the Quotes, Invoices, Clients and Activity lists.
  - Brand also remembers your hourly rate, so a new line in hours starts at it.
  - Brand → Settings shows a Quote Pilot fee: a percentage (3% to start) of the payments recorded
    this month and last. It's a figure only; nothing is charged.
- **File menu:** Import from Invoice Generator Backup…, Export Payments for Tax Time…, Back Up To…,
  Restore Backup…, Start Fresh… and Reset Quote and Invoice Numbers…. Restore Backup… restores the
  daily backup you pick, with no extra question. The status bar says which backup came back.
  - **Money records:** every change rewrites a CSV per financial year for your accountant (invoices
    sent, payments, receipts) in `~/Documents/Quote Pilot/Records/`; File → Show Money Records opens it.
- Every change saves as you make it, with a daily backup. If the library file is ever damaged,
  Quote Pilot won't save over it and offers the latest backup instead. Every mailed PDF is also kept
  in `~/Documents/Quote Pilot/<year>/`.

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

## Updates and releases

To release: change `CFBundleShortVersionString` (and `CFBundleVersion`) in `Resources/Info.plist`,
commit that to `main`, then run `scripts/release.sh 1.1.0`. It tests, builds, zips, tags and
publishes `QuotePilot-mac.zip` as a GitHub release, and edits no file itself.

Quote Pilot checks GitHub for a newer release every time it starts, in the background, and says
nothing if the check fails. A newer release shows a banner under the toolbar ("Quote Pilot 1.1.0 is
ready.") and a note in the status bar. It installs only when you choose Install Update (on the
banner, or Help → Install Update…) and confirm; Later hides the banner until the next launch. The check sends
nothing about you or your work, only the app's version number. Help → Check for Updates… checks
at once. So does Check for Updates on Brand → Settings, which shows the version and answers on the
tab instead of in a box. Each update is written to `~/Library/Logs/Quote Pilot/update.log`, and the old app goes
to the Trash.

## Licence

MIT. See `LICENSE`.
