# Quote Pilot: design spec

Date: 15 October 2026. Status: **approved by the user** ("build it", 15 Oct 2026). Renamed from
"Ticked" to **Quote Pilot** the same day, at the user's request.

Quote Pilot is a simple, well-made Mac app for running the paperwork side of a one-person business. You
send a quote, the client ticks the lines they want and sends it back, you invoice for what they
accepted, and you can see at a glance what you've been paid and what you're still waiting on.

## 1. What the user asked for

Settled in conversation on 15 Oct 2026:

- **A native Mac app, simple, for one person.** Data stays on this Mac. A new **public** GitHub repo.
- **Quote → acceptance → invoice → payment.** A quote is a set of recommendations. The client
  accepts some or all of the lines, and you invoice for the accepted lines.
- **Every quote line has an ID and a tick box.** The quote PDF is fillable. Every box starts
  **unticked**, and an **"Accept all"** box sits at the top. The client ticks, saves and sends it back.
  Quote Pilot reads the returned PDF and works out which lines were accepted and which were declined. If a
  client can't fill the form (Gmail's web preview, printing and scanning), **you tick the lines in the
  app yourself.**
- **Payment plans on the quote:** **50/50** (half on acceptance, half on completion) and **full
  amount**. For 50/50, accepting the quote drafts a deposit invoice for half of the accepted lines,
  and clicking **Job complete** drafts the final invoice for the balance. Each invoice is tracked on
  its own.
- **Invoices that aren't from a quote** (extra hourly work, a monthly fee) are allowed.
- **One brand:** your logo, a heading typeface loaded from a font file, an accent colour, business
  and payment details, and default wording.
- **A dashboard as the main screen:**
  - waiting to be paid, with overdue invoices first
  - received this month and this financial year
  - invoiced this financial year
  - quotes waiting on a reply
  - accepted jobs with money still to invoice
  - every quote and invoice, filterable
  - a spreadsheet export of payments received, for tax time
- **Emails through Mail, for quotes, invoices and receipts.** Quote Pilot opens a Mail draft with the PDF
  attached; **you press Send. The app never sends anything itself.** No payment reminders for now.
- **No GST.** The user doesn't charge it. GST is a toggle, off by default.
- **Build it, then shape it while using it.**

## 2. Calls made for you (overrule any of these)

| Decision | Choice | Why |
|---|---|---|
| Name | **Quote Pilot** (the user's pick, 15 Oct 2026); repo `jimhoggey/QuotePilot-App`, public, MIT licence | A sibling to Runsheet Pilot; matches the `-App` repo names |
| Mac version | macOS 14 (Sonoma) and later | Modern SwiftUI; this Mac runs 26 |
| Where data lives | One library file in `~/Library/Application Support/Quote Pilot/`, saved safely after every change, with an automatic backup copy each day (the last 30 kept) and **File → Back up to…** for a copy anywhere | Simple, private, recoverable |
| Sent PDFs | Every PDF that goes into a Mail draft is also saved to `~/Documents/Quote Pilot/<year>/` | A permanent record of exactly what each client received |
| Body font | A built-in system font. Your loaded font is for headings and the big amount | Fine print stays readable whatever display font you choose |
| Logo files | PNG, JPG or PDF (a PDF logo stays sharp at any size) | macOS draws all three reliably into PDFs |
| "Full amount" plan | One invoice for the accepted total, drafted when you click **Job complete** | Small jobs are usually billed when done |
| Billing early | On any accepted quote, **Draft invoice now** drafts the next invoice the plan calls for: the deposit if there isn't one yet, otherwise the final or full invoice | One button, no guessing which invoice comes next |
| Was it sent? | After the Mail draft opens, Quote Pilot asks "Did you send it?" and only marks it Sent when you say yes | Mail doesn't tell other apps whether a message was sent |
| Numbers | `Q-0001` and `INV-0001`, continuing from the highest number used (imports included). A number is never reused. Sent invoices can be **voided**, not deleted; drafts can be deleted | Clean records; no duplicate numbers |
| Line IDs | `01`, `02`, … per quote. They renumber freely while the quote is a draft and are **frozen once it's sent** | The client's ticks must still match after you reorder |
| Money | Stored as whole cents; quantities can have decimals (1.5 hrs). Each line rounds to the cent | No floating-point pennies going missing |
| Currency | AUD, set once on the Brand page | One business, one currency |
| Left out | Discounts, several brands, reminders, multi-currency, iPhone, cloud sync, online payments, expenses, auto-update | Not asked for. Easy to add later |

## 3. Approaches considered

1. **A Swift package with three parts, a core, PDFs and the app, built with Apple's Command Line Tools
   (chosen).** The money rules and PDF code sit apart from the screens, so they get proper automated
   tests (Swift Testing ships with the Command Line Tools on this Mac). A `build.sh` wraps the result
   into `Quote Pilot.app`. No Xcode needed.
2. **One big Swift file, like Booth Check.** Fastest to start, but Booth Check's single file has
   reached 212 KB. Money code deserves smaller, tested pieces.
3. **Install Xcode and use an Xcode project.** A 10 GB+ install and a project file to babysit, for
   nothing the Command Line Tools can't do here.

For the PDFs: **drawn directly with Core Text (chosen)** rather than built as HTML and printed through
WebKit. Drawing directly means Quote Pilot knows exactly where every line and tick box lands on every page,
which the fillable form depends on. It also embeds your font and splits long quotes across pages
predictably.

## 4. How it fits together

```
QuotePilotCore   pure Swift, no UI. Models, money maths, payment plans, statuses, numbering,
             dashboard figures, financial years, CSV export, import from the old HTML tool,
             loading and saving the library, backups.
QuotePilotPDF    Core Text + PDFKit. Draws quote, invoice and receipt PDFs from a model, adds the
             tick-box form to quotes, and reads ticks back out of a returned PDF.
QuotePilotApp    SwiftUI. Windows, editors, dashboard, drag-and-drop, Mail drafts, activity log.
```

QuotePilotApp depends on the other two; QuotePilotPDF depends on QuotePilotCore; QuotePilotCore depends on nothing.

## 5. The data

- **Brand:**
  - business name, logo, heading font file, accent colour, details (ABN, email, phone, address,
    website) and payment details (bank, BSB and account, or PayID)
  - default terms for quotes and invoices
  - email wording for quotes, invoices and receipts, with placeholders such as `{client}`,
    `{number}`, `{amount}` and `{due}`
  - the GST toggle (off) and the currency (AUD)
  - default days: payment due 14, quote valid 30
- **Client:** name, contact person, email (needed to send), phone, address, notes.
- **Quote:**
  - number, client, title (e.g. "Website rebuild, phase 1"), issued date, valid until
  - payment plan (50/50 or full amount)
  - lines, a work summary (plain text; lines starting with `-` become dot points), terms
  - status, when it was sent, the acceptance record, when the job was completed
- **Quote line:** ID, title, optional detail, quantity, unit (hrs, days or units), rate, decision
  (none, accepted or declined).
- **Acceptance record:** when it was recorded, how it was recorded (returned PDF or ticked by hand),
  the PDF's file name, the client's name and date from the form, and the accepted and declined line
  IDs.
- **Invoice:**
  - number, client, the quote it came from (if any), kind (deposit, final, full or standalone)
  - issued date, due date, lines, any earlier invoices it subtracts (a final invoice subtracts the
    deposit invoice)
  - status, when it was sent, payments, when a receipt was sent
- **Payment:** date, amount, method (bank transfer, cash, card or other), note.
- **Activity log entry:** time, document number, what happened.

### Money rules

- Line amount = quantity × rate, rounded to the cent. Quote total = all lines. Accepted total =
  accepted lines only.
- **50/50:** deposit = half the accepted total, rounded to the cent. The final invoice lists every
  accepted line, subtracts the deposit invoice ("Less deposit, INV-0004"), and asks for the rest. The
  two always add up exactly to the accepted total.
- **Full amount:** one invoice for the accepted total.
- **Standalone:** the total of its own lines.
- **GST (if ever switched on):** 10% on top of quotes and invoices; "accepted total" and the 50/50
  split then include it. The invoice title becomes "Tax invoice", with the ABN shown.
- **Amount owing** on an invoice = total − payments recorded.

### Statuses

- **Quote:** Draft → Sent → Accepted (shown as "Accepted, partly" when some lines were declined) or
  Declined. A sent quote past its valid-until date shows as **Expired**; an acceptance can still be
  recorded, with a warning.
- **Invoice:** Draft → Sent → Part paid → Paid, or **Void**. A sent or part-paid invoice past its due
  date shows as **Overdue**.

### Dashboard figures

- **Waiting to be paid:** amount owing on every Sent and Part paid invoice. Overdue ones are listed
  first, with days late.
- **Received:** payments dated this month, and this financial year (1 July to 30 June, labelled e.g.
  "FY 2026–27").
- **Invoiced this financial year:** totals of invoices issued this FY that aren't Draft or Void.
- **Quotes waiting on a reply:** Sent quotes not yet accepted or declined, with their value.
- **Still to invoice:** accepted quotes whose invoices don't yet add up to the accepted total (the
  second half of a 50/50 job, for example).
- **Tax-time export:** a CSV of payments received in a chosen FY (date, client, invoice, amount,
  method).

## 6. Screens

- **Sidebar:** Dashboard, Quotes, Invoices, Clients, Activity, Brand. The toolbar has **New quote** and
  **New invoice**.
- **Quote editor:**
  - **Form on the left:** client, title, dates, payment plan, lines, work summary, terms.
  - **Live PDF preview on the right.**
  - **Actions:** Send by Mail, Record acceptance (drop the returned PDF, or tick lines by hand), Job
    complete, Draft invoice now, Duplicate.
- **Acceptance review sheet:**
  - Shows every line as the PDF reported it, with the accepted total and the client's name and date
    from the form.
  - You can change any tick before confirming.
  - Confirming records the acceptance, and for 50/50 drafts the deposit invoice and opens it.
- **Invoice editor:**
  - Laid out like the quote editor.
  - **Actions:** Send by Mail, Record payment, Send receipt (once a payment exists), Void.
- **Drop a returned PDF anywhere** in the window, or use **File → Read returned quote…**. Quote Pilot finds
  the quote from the form itself.
- **Clients:** a list and a simple form.
- **Brand:** everything in the Brand data above, with a live sample PDF.
- **Activity:** every Mail draft opened, every "sent" confirmation, every acceptance read (with the
  file name), every payment and status change, newest first.
- **File → Import from Invoice Generator…** reads the old HTML tool's backup file.

## 7. PDFs

- **Look:** carried over from the existing HTML tool:
  - one A4 page, multi-page when needed, with the table header repeated
  - the heading font for the title and the big amount
  - indigo ink and the brand's accent colour
  - empty fields left off the page
  - PDFs named `<number> <client>.pdf`
- **Quote PDF:**
  - The line table gains an **ID** column and an **Accept** tick-box column.
  - Above the table: **Accept all** and a one-line instruction ("Tick the lines you'd like, or Accept
    all, then save and send this PDF back").
  - Below the totals: **Name** and **Date** fields for the client to type into.
  - The payment plan is spelled out ("50% when accepted, 50% on completion").
- **Form field names** carry the quote number, so a returned PDF identifies itself:
  `quotepilot_Q-0007_all`, `quotepilot_Q-0007_line_03`, `quotepilot_Q-0007_name`, `quotepilot_Q-0007_date`
  (underscores, because PDF reserves '.' for field hierarchy). The PDF's title and keywords also carry the number.
- **Reading a returned PDF:**
  - **Accept all ticked:** every line is accepted.
  - **Otherwise:** ticked lines are accepted and unticked lines declined.
  - **Nothing ticked at all:** Quote Pilot asks whether the client declined everything or their app lost
    the ticks.
  - **No form at all** (the client's app flattened it): Quote Pilot says so and opens the hand-ticking view.
  - **Number not matching any quote, or line IDs that don't exist:** Quote Pilot says exactly what didn't
    match and changes nothing.
- **Invoice PDF:**
  - No form.
  - A deposit invoice lists the accepted lines for reference, then a "Deposit, 50%" amount.
  - A final invoice subtracts the deposit.
  - Payment details and due date are prominent.
- **Receipt PDF:** titled "Receipt", referencing the invoice. Lists the payments received, the total
  paid and any balance left.

## 8. Mail

- Quote Pilot uses macOS's own "compose email" share service. It opens a new message in Mail containing:
  - the client's address
  - the brand's subject and wording, with the placeholders filled in
  - the PDF attached
- **You review it and press Send in Mail.** Quote Pilot then asks "Did you send it?". **Yes** marks the
  document Sent and logs it; **Not yet** changes nothing.
- **No client email:** Quote Pilot asks for one before opening Mail.
- **The compose service is unavailable:** Quote Pilot shows the PDF in Finder and copies the message to
  the clipboard, and says so.

## 9. Importing from the old HTML tool

- **File → Import from Invoice Generator…** reads the JSON from its "Back up to file" button.
- **Mapping:**
  - each document becomes a quote or a standalone invoice, keeping its number, dates, lines,
    summary and terms
  - clients are created from the "Billed to" names
  - the logo goes to the Brand page if there isn't one yet
  - imported documents arrive as **Sent**, with no payments; you record payments and acceptances
    yourself
- **Repeat imports** skip numbers that already exist, and the import lists what it did.

## 10. Keeping data safe

- **Saving:** every change saves the whole library to a temporary file first, then swaps it in. A
  crash mid-save can't damage it.
- **Backups:** on launch, and once a day, Quote Pilot copies the library into `Backups/` (the last 30
  kept).
- **Unreadable library:** Quote Pilot never overwrites it. It explains, keeps the file, and offers to
  restore the latest backup.
- **Format version:** the file carries one, so later versions can upgrade it.
- **No silent failures:** anything that fails to save, read or open Mail shows a clear message and
  goes into the Activity log.

## 11. Testing

- **QuotePilotCore, with Swift Testing (`swift test`):**
  - line rounding
  - 50/50 splits that always add up, including odd cents
  - statuses, including overdue and expired at day boundaries
  - numbering after imports and voids
  - dashboard figures and financial-year edges (30 June / 1 July)
  - the CSV output
  - import mapping, against a sample backup made from made-up data
  - save, load and backup, including an unreadable file
- **QuotePilotPDF:**
  - **Round trip:** generate a quote PDF, tick boxes in code with PDFKit, save, read it back, and
    check the accepted and declined lines.
  - **Error cases:** "Accept all" alone, nothing ticked, a flattened PDF, a quote-number mismatch,
    unknown line IDs.
  - **Layout:** a long quote breaks across pages with every tick box on the right page.
  - The custom heading font ends up embedded.
- **App:** it builds, launches and shows the dashboard. Screens are also rendered to images for a
  visual check.
- **Real-world check early on (needs you, once):** open a generated quote in Preview, tick two lines,
  save, and drop it back into Quote Pilot. Preview is what most clients will use, so this proves the core
  idea before everything else is built on it.

## 12. Repo and project setup

- **Public repo `jimhoggey/QuotePilot-App`:**
  - README, MIT licence, and made-up sample data only
  - git-ignores `CLAUDE.md`, `Invoice Generator.html` (it holds real client details), build output
    and any backup or PDF files
- **Local folder:** it stays `~/Claude/Projects/FynnProjectManagement/QuoteInvoiceBuilder`.
- **Builds:** `./build.sh` → `build/Quote Pilot.app`, ad-hoc signed. `swift test` runs the tests. Releases
  and auto-update come later, if wanted.

## 13. Build order (each step usable on its own)

1. Package skeleton, QuotePilotCore models and money rules, with tests.
2. The quote PDF with its tick-box form, plus the round-trip reader, then **the real-world Preview
   check**.
3. App shell, Brand, Clients, and the quote editor with live preview.
4. Mail drafts and the "Did you send it?" step. Activity log.
5. Recording acceptance (returned PDF and by hand), and drafting the deposit invoice.
6. Invoice editor, Job complete (final and full-amount invoices), Draft invoice now, payments,
   receipts, void.
7. Dashboard and the tax-time CSV.
8. Import from the HTML tool, backups and restore, README, and the public repo.

## 14. Risks

- **Not every PDF app can fill forms**, and some flatten them on save. Mitigation: hand-ticking in
  the app, a clear instruction line on the quote, and a clear message when a returned PDF has no
  form.
- **The Command Line Tools on this Mac were broken** (found 15 Oct 2026): leftovers from a macOS 27
  beta made `swift-package` crash and gave the 6.3.3 compiler an SDK it can't read. The fix is
  installing Command Line Tools for Xcode 27.0 (offered by Software Update). Step 1 confirms that
  `swift build` and `swift test` work before anything else is built.
- **Mail must be set up with an account** for the compose service to work; the fallback covers it.
