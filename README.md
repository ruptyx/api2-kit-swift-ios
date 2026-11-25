# Hesabe iOS SDK: KNET, cards, saved cards and Apple Pay with no keys in the app

The SDK takes one payment session from your server and does the rest: it shows the
payment, follows the customer through KNET, 3-D Secure or Apple Pay, asks Hesabe how the
payment ended, and returns that to your app. Cards are entered in Hesabe's embedded card
form inside the app, which can also save the card for your server to charge later.

Your merchant keys stay on your server. The app holds the session's `data` string, which
opens one payment and cannot create another. The SDK does no encryption.

`Sources/` is the Swift package. [`demo/`](demo) is a complete app that runs against the
sandbox from Xcode with nothing else to start: one file in it stands in for your server.
[`hosting/apple-pay.html`](hosting/apple-pay.html) is the page behind the Apple Pay
button, the one file that is hosted.

Status, November 2026: every Hesabe call the SDK makes was run against the sandbox. The
package and the demo app are compiled, and the package unit tested, by GitHub Actions.
An earlier version of the demo, with the keys in a small server beside it, ran on an iOS
simulator against the sandbox: a KNET payment, a card payment in the card form with 3-D
Secure, a payment that saves the card, a card saved without a charge, a charge on a saved
card, and removing a card. A declined card was run in the card form in a desktop browser
presenting itself as an iPhone web view. The Apple Pay button has not been run yet, and
nothing has been run on an iPhone.

Newer than those runs, compiled by GitHub Actions and not yet run on a simulator: the
sheet's loaders and logos, the demo's result screen, payment history and saved-card
confirmations, and the demo creating its own sessions.

## What you need before starting

1. A Hesabe merchant account with its keys from Merchant Panel, Profile, Merchant Keys:
   merchant code, access code, secret key (32 characters), IV key (16 characters). They go
   on your server, never in the app.
2. A server endpoint that calls Hesabe's Checkout API. Step 1 describes it.
3. For cards in the embedded form and for saved cards: Direct Payment (MPGS) enabled on
   your account (email support@hesabe.com).
4. For the Apple Pay button: Apple Pay enabled on your account (email support@hesabe.com)
   and the address of the hosted button page.
5. Xcode 16 or later. The SDK supports iOS 15 and later.

## Step 1. Create the session on your server

Your server sends the usual Checkout API request, encrypted with your keys, to
`POST https://api.hesabe.com/checkout` (`https://sandbox.hesabe.com/checkout` for the
sandbox). This is the payload before encryption:

```json
{
  "merchantCode": "842217",
  "amount": "1.000",
  "currency": "KWD",
  "paymentType": 0,
  "orderReferenceNumber": "ORDER-1001",
  "responseUrl": "https://example.com/hesabe/return",
  "failureUrl": "https://example.com/hesabe/return",
  "version": "2.0"
}
```

- `paymentType` is `0`. The app chooses the method, so one session serves every method.
- `responseUrl` and `failureUrl` are the same two URLs for every payment. Nothing has to
  exist at them: the SDK stops the navigation before it loads.
- `amount` is a string with exactly three decimals.

Hesabe answers with a `token` and `response.data`. Return `response.data` to the app. It
is a hex string of about 190 characters.

The endpoint your app calls is yours to shape. The app says what was ordered, never what
it costs, and gets the session back. This is the one the demo is written against:

```http
POST /payments/session
{"quantity": 2}

200 OK
{"data": "9e5a960d...", "token": "842217...", "reference": "ORDER-1001", "amount": "0.500"}
```

`data` is all the SDK takes. `token` is what your server looks the payment up by
afterwards, and `reference` and `amount` name the payment in the app.

Check: open `https://sandbox.hesabe.com/payment?data=` followed by that string in a
browser. Hesabe's payment page appears.

## Step 2. Add the package

In Xcode, choose File, Add Package Dependencies, enter this repository's URL, and add the
`HesabeUI` product to your app target.

Check: `import HesabeUI` compiles.

## Step 3. Configure the SDK

```swift
import HesabeUI

let configuration = HesabeConfiguration(
    environment: .sandbox,
    returnURLs: ReturnURLs(URL(string: "https://example.com/hesabe/return")!),
    merchantDisplayName: "Example Store"
)
```

`returnURLs` are the `responseUrl` and `failureUrl` from Step 1. The SDK ends the payment
when Hesabe navigates to either.

## Step 4. Present the checkout

```swift
let session = try HesabeSession(data: dataFromYourServer)
let sheet = HesabeCheckoutSheet(configuration: configuration)

switch await sheet.present(session, methods: [.knet, .card], from: self) {
case .paid(let transaction):
    showReceipt(transaction.orderReference)
case .cardSaved:
    reloadSavedCards()
case .failed, .canceled, .notStarted:
    offerToPayAgain()
case .pending, .unconfirmed:
    showOrderIsBeingChecked()
}
```

In SwiftUI:

```swift
.hesabeCheckout(session: $session, configuration: configuration, methods: [.knet, .card]) { result in
    handle(result)
}
```

`methods` decides what the customer sees:

| `methods` | The customer sees |
|---|---|
| one method, `[.knet]` | That method's page directly. |
| `[.card]` | Hesabe's embedded card form: the card fields and a pay button, with 3-D Secure in the same sheet. |
| several, `[.knet, .card, .amex]` | A native list of those enabled on your account, each with its logo, then the chosen method. |
| none | Hesabe's Indirect Method: its own hosted page, where the customer chooses among every enabled method. |

A payment method is Hesabe's payment type id: `.knet` is 1, `.card` is 2 (MPGS), `.amex`
is 7. Any other id works as `PaymentMethod(rawValue: 18)`. Google Pay, type 16, is not
part of the iOS SDK: the method list never offers it.

The logos are Hesabe's own, fetched from Hesabe's assets bucket by payment type id
(`PaymentMethod.logoURL`) and drawn on a white badge. For your own buttons and rows,
`HesabeMethodLogo(.knet)` is the same badge in SwiftUI and
`await HesabeLogos.badge(for: .knet)` is its image in UIKit. A method Hesabe has no logo
for shows its name alone.

The sheet is on screen as soon as you call it. It shows a loader while it reads the
session, while the payment page opens ("Connecting to KNET…", "Opening secure card
form…") and while it asks Hesabe how the payment ended, so a tap is always answered.
A lost connection while the session is read is reported in the sheet with a "Try again"
button. The texts are in `HesabeStrings`, in English and Arabic.

The card form is Hesabe's page at `pay/webview`, shown in the sheet under your app's own
title bar. The card number is typed into Hesabe's page and sent by it to Hesabe: it never
passes through your app's code or your server. A card type the form does not take for
the session opens Hesabe's payment page instead.

Check: on the sandbox, pay with KNET test card `8888880000000001`, expiry `09/30`, PIN
`1234`. The sheet shows "Payment complete" and returns `.paid`. Then pay with `[.card]`
and test card `5123450000000008`, expiry `01/39`, security code `100`. Expiry `05/39` is
declined and returns `.failed`.

### The seven results

| Result | Meaning | What the app does |
|---|---|---|
| `.paid` | Hesabe confirms the payment. | Show the receipt. |
| `.cardSaved` | Hesabe stored the card and charged nothing. See Step 6. | Reload the saved cards. |
| `.failed` | Hesabe recorded the attempt and it did not go through. | Offer to pay again with a new session. |
| `.pending` | Hesabe has the payment and has not settled it. | Do not charge again. Check later. |
| `.canceled` | The customer closed the payment and Hesabe has no transaction. | Nothing was charged. |
| `.unconfirmed` | The flow ended and Hesabe could not be asked. | The customer may have been charged. Check from your server. |
| `.notStarted` | The session was refused or the page never loaded. | Nothing was charged. Create a new session. |

`.paid`, `.cardSaved`, `.failed` and `.pending` carry Hesabe's record of the payment as a
`HesabeTransaction`: the status, amount, order reference, payment and transaction ids,
track id, terminal and Hesabe's own date. Its `rawJSON` is the whole record for a
developer to read. It includes the customer's name, email and mobile number, so keep it
out of logs.

## Step 5. Add the Apple Pay button

```swift
HesabeApplePayButton(
    session: session,
    configuration: configuration,
    method: .applePayKNETDebit,
    type: .buy,
    style: .automatic,
    cornerRadius: 8
) { result in
    handle(result)
}
```

Set `applePayPageURL` in the configuration to the hosted button page:

```swift
configuration.applePayPageURL = URL(string: "https://example.com/apple-pay.html")!
```

- `method` is the Apple Pay payment type on your account: `11` KNET debit, `13` KNET
  international, `9` MPGS.
- `type` is the wording (`plain`, `buy`, `checkout`, `book`, `subscribe`, `donate`,
  `order`). `style` is `automatic`, `black`, `white` or `whiteOutline`.
- Closing the Apple Pay sheet is not a result. The button stays ready.

### Why the button is a web view

Apple Pay through Hesabe starts from a web page on a domain registered with Apple, and
WebKit refuses to start it from a page inside the app. So the button is WebKit's own
Apple Pay button, drawn by [`hosting/apple-pay.html`](hosting/apple-pay.html) in a web
view the size of the button. The page is the same file for every payment and holds no
keys. The payment's settings travel in the URL fragment, which browsers never send to a
server.

An earlier version of this page took a production payment in September 2026, from a
merchant's own domain and with an embedded session. It has not been run with a plain
session, or from a page hosted by Hesabe, yet.

## Step 6. Save cards and charge them later

Saved cards belong to a Hesabe customer, and every call that touches them needs your
keys, so they are your server's. The app shows the card form and the list.

| What happens | Who does it | Hesabe call |
|---|---|---|
| Create the customer, once per user | Your server | `POST api/direct-payment/customer` |
| Offer to save the card during a payment | Your server, in the session | `POST checkout` with `saveCard` and `customer_id` |
| Save a card without a charge | Your server, in the session | `POST checkout` with amount `0.000`, `saveCard` and `customer_id` |
| Enter the card | The SDK | Hesabe's card form |
| List the customer's cards | Your server | `GET api/direct-payment/cards` |
| Pay with a saved card | Your server | `POST api/direct-payment/charge-card` |
| Remove a card | Your server | `DELETE api/direct-payment/cards/{cardId}` |

### On your server

A session that offers to save the card carries the customer. These three fields join the
payload from Step 1, and `version` becomes `"3.0"`:

```json
{
  "saveCard": true,
  "customer_id": 4026,
  "version": "3.0"
}
```

The card form then shows "I agree that my card details will be securely saved". With
amount `"0.000"` the form's button reads "Save Card", nothing is charged, and the SDK
returns `.cardSaved`.

[`SandboxMerchantServer.swift`](demo/HesabeDemo/SandboxMerchantServer.swift) in the demo
makes each of these calls, in the place of your server. This is its saved-card charge:

```swift
// With the customer on the charge, Hesabe refuses a card saved by anyone else.
// Sent once and never again: Hesabe has no idempotency keys, so a retry is a
// second charge.
let answer = try await send("POST", "api/direct-payment/charge-card", [
    "card_id": card.id,
    "amount": amount,
    "customer_id": customer,
    "order_reference": reference,
])
```

A charge has no page and no 3-D Secure: Hesabe authenticated the card when it was saved.
The answer to your server is the result, `CAPTURED` when paid.

### In the app

Add a card with the same sheet. The session decides what the sheet shows:

```swift
let session = try HesabeSession(data: zeroAmountSessionFromYourServer)
if case .cardSaved = await sheet.present(session, from: self) {
    reloadSavedCards()
}
```

`HesabeSavedCard` decodes each entry of Hesabe's `cards` list unchanged, so your server
can pass the list through:

```swift
struct CardList: Decodable { let cards: [HesabeSavedCard] }

let cards = try JSONDecoder().decode(CardList.self, from: dataFromYourServer).cards
Text(cards[0].displayName)  // Mastercard •••• 0008
```

To pay with a saved card, the app sends its `id` to your server, and your server charges
it. The card form does not list saved cards in an app, and it refuses a card the customer
has already saved: "This card is already saved. Please use your saved card to proceed."

Check: on the sandbox, add card `5123450000000008`. The sheet shows "Card saved", your
server's list has one card, and a charge of `0.750` on it answers `CAPTURED`.

## Step 7. Settle payments the app never saw finish

A customer can pay in a banking app and never come back, and iOS can close the app during
3-D Secure. The SDK writes each session token down before the payment page opens. Call
this once at launch:

```swift
let settled = await HesabeClient(environment: .sandbox).recoverPayments()
```

It returns the payments that have since been paid, saved or failed.

## Run the demo

The demo is the integration above as a complete app: one product, a quantity, the
checkout sheet four ways, saved cards, and the Apple Pay button. Open
`demo/HesabeDemo.xcodeproj` in Xcode and run it on a simulator. There is nothing else to
install or start.

### The keys in the demo are for the sandbox only

A demo that runs by itself has no server to keep the keys on, so
[`SandboxMerchantServer.swift`](demo/HesabeDemo/SandboxMerchantServer.swift) does a
server's work inside the app: it holds Hesabe's published sandbox keys, encrypts with
them and calls `https://sandbox.hesabe.com`. It is fixed to the sandbox and it is not
part of the SDK. `Sources/` holds no keys and no encryption.

Do not ship that file and do not copy it into an app. Anything compiled into an app can
be read out of it, so keys in an app are keys anyone can use: to create sessions for any
amount, to read your transactions and to charge your customers' saved cards. In a live
app the merchant keys and that code are on your server, and each of the file's methods
is one endpoint the app calls over HTTPS:

| The app calls | It sends | Your server answers |
|---|---|---|
| `POST /payments/session` | `{"quantity": 2, "saveCard": false}` | `{"data": "9e5a960d...", "token": "842217...", "reference": "ORDER-1001", "amount": "0.500"}` |
| `POST /payments/confirm` | `{"token": "842217..."}` | `{"paid": true, "status": "SUCCESSFUL", "transaction": {...}}` |
| `POST /cards/session` | `{}` | The same answer as `/payments/session`, with amount `"0.000"`. |
| `GET /cards` | | `{"cards": [...]}`, Hesabe's list unchanged. |
| `POST /cards/charge` | `{"cardId": 2001, "quantity": 2}` | `{"paid": true, "status": "CAPTURED", "amount": "0.500", "reference": "ORDER-1002"}` |
| `POST /cards/remove` | `{"cardId": 2001}` | `{"removed": true}` |

The paths are yours to name. Your server takes the customer from its own login, never
from a value the app sends.

### What the demo shows

- The stand-in server holds the price. The app sends a quantity and receives a session.
- A pay button shows a spinner from the tap until the payment has a result, and nothing
  else can be started meanwhile.
- "Indirect Method" opens Hesabe's hosted payment page, where the customer chooses the
  method.
- Every payment ends on a result screen: the status, Hesabe's details of the payment,
  what the SDK reported beside what the server confirmed with Hesabe, and Hesabe's
  answers as JSON with a Copy button. Only the server's answer may release an order.
- A failed payment offers "Try again", which takes a new session. A pending or
  unconfirmed one offers "Check status again".
- "Payment history" keeps the last 50 results on the device and reopens any of them.
- "Offer to save the card" puts the demo's customer on the session. "Add a card" saves one
  without a charge. Tapping a saved card asks "Pay KWD 0.250 with Mastercard •••• 0008?",
  then the server charges it. Swiping a card, or Edit, removes it after a confirmation.
  The demo creates one Hesabe customer and remembers it on the device.
- A payment the app never saw finish is settled at the next launch and opens as a
  result.
- What the app is told is in `demo/HesabeDemo/Config.swift`: the return URL, the Apple
  Pay page and the price it shows.

## How the SDK works

| File | What it does |
|---|---|
| `Hesabe/HesabeSession.swift` | Holds the session's `data`. Unwraps an embedded session. |
| `Hesabe/HesabeClient.swift` | The keyless calls: session details, payment page and card form addresses, outcome. |
| `Hesabe/HesabeTransaction.swift` | A payment as Hesabe recorded it, and the seven results. |
| `HesabeUI/HesabeCheckoutSheet.swift` | Reads the session, shows the method list, the card form or the page, settles the result. |
| `HesabeUI/HesabeLogos.swift` | Hesabe's logo for each method, fetched once and drawn on a badge, for the method list and for your own screens. |
| `HesabeUI/PaymentWebViewController.swift` | Hesabe's page or card form in a web view: bank app hand-off, 3-D Secure popups, return detection. |
| `HesabeUI/StatusView.swift` | What the sheet shows between pages: a loader with a line of text, the settled result, a failure with "Try again". |
| `Hesabe/HesabeSavedCard.swift` | One saved card as Hesabe lists it, for your server to pass through. |
| `HesabeUI/HesabeApplePayButton.swift` | The Apple Pay button and its loading, processing and retry states. |
| `Hesabe/HesabePendingPayments.swift` | The tokens of payments in flight, kept across launches. |

The Hesabe calls, as run on the sandbox in November 2026:

| Call | Answer |
|---|---|
| `GET api/checkout-details?data=<data>` | The session's token, amount, currency and enabled payment types. |
| `GET payment?data=<data>` | Hesabe's page with every method. |
| `GET payment?data=<data>&paymentType=1` | A redirect straight to KNET. |
| `GET pay/webview?data=<data>&locale=en` | The embedded card form. HTTP 403 to anything but an in-app web view. |
| `GET api/transaction/enquire/<token>` | The transaction once one exists; 404 "Transaction not found" before. `SUCCESSFUL` when paid, `FAILED` when declined, `AUTHORIZED` with amount `0.000` for a saved card. |

### Things that matter

- The result comes from `api/transaction/enquire`, never from the redirect. Reaching
  `responseUrl` proves nothing, and the Apple Pay sheet says "Done" before Hesabe answers.
- The result is for the screen. Release the order from your server, which asks Hesabe's
  Transaction Enquiry itself or acts on the webhook by looking the payment up.
- A session is single use. After any result except `.notStarted`, the next attempt needs
  a new session.
- Send `response.data` to the app, not `token`. The payment page does not open with the
  token.
- Hesabe serves the card form to in-app web views only. The SDK asks for the mobile page,
  because an iPad web view asks for desktop pages by default and gets HTTP 403.
- The card form works with the plain session from Step 1. `channel` and `paymentType` 2
  are not needed for it.
- A saved-card charge is one request with no page. Your server sends it once and never
  retries it: Hesabe has no idempotency keys.
- The SDK injects no script into its web views. WebKit turns Apple Pay off in a web view
  the app has injected script into.
- Amounts are shown as Hesabe reports them, never computed on the device.
- The logos come from `hesabe-assets-ir.s3.eu-west-1.amazonaws.com`, a host other than
  the gateway. Where an app or a network allows only named hosts, the list shows the
  names alone until that host is allowed.

## If something goes wrong

- `.notStarted(.rejected("Failed to decrypt data parameter"))`: the string is not
  `response.data`, the session was already used, or it was created on the other
  environment.
- `.notStarted(.configuration("none of the requested payment methods is enabled..."))`:
  the methods you passed are not enabled on the account. Ask Hesabe to enable them.
- The sheet stays on your own return page: `returnURLs` does not match the `responseUrl`
  your server sent.
- `.notStarted(.rejected("the payment page answered HTTP 403"))`: Hesabe refused to serve
  the card form. It is served to in-app web views only.
- The card form has no "save" checkbox: the session has no `customer_id`, or `saveCard`
  is not `true`.
- The card form says "This card is already saved": charge the saved card from your server.
- Your server gets "Too Many Attempts": the saved-card calls allow 30 a minute.
- `.unconfirmed(.noTransaction)` after the customer returned: Hesabe had not recorded the
  payment within ten seconds. Look it up from your server.
- The Apple Pay button shows "Try again": the message beside it says why. The usual
  causes are a missing `applePayPageURL` and an Apple Pay type that is not enabled.
- KNET opens and nothing happens after the bank app: the bank app did not return. The
  payment is settled by Step 6 at the next launch.

## Licence

MIT
