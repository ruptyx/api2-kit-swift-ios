# The Apple Pay button page

`apple-pay.html` is the one file in this repository that is not Swift, and the one file
that is hosted instead of compiled.

Apple Pay through Hesabe starts from a web page served over HTTPS from a domain
registered with Apple. WebKit refuses to start it from a page inside an app, so the page
cannot ship in the SDK. `HesabeApplePayButton` shows it in a web view the size of the
button.

- The page is static: no build step, and the same file for every payment.
- It holds no keys. Each payment's settings arrive in the URL fragment, which browsers
  never send to a server.
- Hesabe's Apple Pay script is pinned by version and checked with an integrity hash.

You host it, on the domain Hesabe has registered with Apple for your account. The
[integration guide](../docs/INTEGRATION.md#add-the-apple-pay-button) has the steps, with
the domain association file.

Give the address the page is served from to `HesabeConfiguration`, as
`applePayPageURL`:

```swift
configuration.applePayPageURL = URL(string: "https://example.com/apple-pay.html")!
```
