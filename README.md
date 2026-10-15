# Quote Pilot

A simple Mac app for the paperwork side of a one-person business: send a quote, let the client tick
the lines they want right on the PDF, invoice for what they accepted, and see at a glance what's been
paid and what's still owed.

**Status:** in progress. The core rules and the PDFs are built and tested. The app's screens come next.

## How it works

1. **Quote.** Every line gets an ID and a tick box, with an "Accept all" box at the top. The client
   ticks, adds their name and the date, saves the PDF and sends it back.
2. **Acceptance.** Drop the returned PDF into Quote Pilot and it reads the ticks. If the client's PDF
   app couldn't fill the form, tick the lines yourself.
3. **Invoices.** Choose a payment plan per quote: **50/50** (a deposit invoice when it's accepted, the
   balance when the job's done) or **full amount**. Only the accepted lines are billed.
4. **Payments.** Record each payment. The dashboard shows what's waiting to be paid, what's overdue, and
   what came in this month and this financial year (1 July to 30 June).
5. **Mail.** Quote Pilot opens a Mail draft with the PDF attached. You always press Send yourself.

Everything stays on your Mac, in `~/Library/Application Support/Quote Pilot`, with a daily backup.

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
