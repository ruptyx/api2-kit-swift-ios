// The demo app's backend. This process is the only place the merchant keys exist:
// the app receives a session's `data` string and nothing else.
//
//   npm install && npm start
//
// Built on node:http with no framework, so the handlers are the whole story.

import { readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { Hesabe, HesabeCardError, HesabeError, isSuccessful } from "hesabe";

const PORT = Number(process.env.PORT ?? 4242);

// Hesabe's published sandbox keys. Yours come from Merchant Panel, Profile, Merchant
// Keys, through the environment, and never reach the app.
const hesabe = new Hesabe({
  merchantCode: process.env.HESABE_MERCHANT_CODE ?? "842217",
  accessCode: process.env.HESABE_ACCESS_CODE ?? "c333729b-d060-4b74-a49d-7686a8353481",
  secretKey: process.env.HESABE_SECRET_KEY ?? "PkW64zMe5NVdrlPVNnjo2Jy9nOb7v1Xg",
  ivKey: process.env.HESABE_IV_KEY ?? "5NVdrlPVNnjo2Jy9",
  environment: process.env.HESABE_ENVIRONMENT ?? "sandbox",
});

// Sent as both responseUrl and failureUrl, and set as `Config.returnURL` in the app.
// Nothing is ever fetched from it: the SDK stops the navigation before it loads.
const RETURN_URL = process.env.RETURN_URL ?? "https://example.com/hesabe/return";

// The server owns the price. The app sends what was ordered, never what it costs.
const PRICE_FILS = 250;
const kwd = (fils) => `${Math.floor(fils / 1000)}.${String(fils % 1000).padStart(3, "0")}`;

function amountFor(quantity) {
  if (!Number.isInteger(quantity) || quantity < 1 || quantity > 20) {
    throw new BadRequest("quantity must be a whole number from 1 to 20");
  }
  return kwd(quantity * PRICE_FILS);
}

// ---------------------------------------------------------------- the customer
// Saved cards belong to a Hesabe customer. The demo has one, remembered in a file
// beside this script. Your server keeps one per user account, in the user's row, and
// takes the user from its own login, never from a value the app sends.
const CUSTOMER_FILE = new URL("./.customer.json", import.meta.url);
const CUSTOMER_KEY = `${hesabe.environment}:${process.env.HESABE_MERCHANT_CODE ?? "842217"}`;
let creatingCustomer = null;

async function existingCustomerId() {
  try {
    return JSON.parse(await readFile(CUSTOMER_FILE, "utf8"))[CUSTOMER_KEY] ?? null;
  } catch {
    return null;
  }
}

async function customerId() {
  const existing = await existingCustomerId();
  if (existing) return existing;
  creatingCustomer ??= (async () => {
    // Hesabe refuses a second customer with the same email or mobile number.
    const stamp = String(Date.now()).slice(-8);
    const customer = await hesabe.customers.create({
      name: "Demo Customer",
      email: `demo-${stamp}@example.com`,
      mobileNumber: stamp,
    });
    await writeFile(CUSTOMER_FILE, JSON.stringify({ [CUSTOMER_KEY]: customer.customer_id }));
    return customer.customer_id;
  })().finally(() => (creatingCustomer = null));
  return creatingCustomer;
}

async function savedCards() {
  const customer = await existingCustomerId();
  return customer ? { customer, cards: await hesabe.cards.list(customer) } : { customer: null, cards: [] };
}

const routes = {
  // The app asks for a payment session.
  "POST /session": async ({ quantity, saveCard }) => {
    const amount = amountFor(quantity);
    const reference = `DEMO-${Date.now()}`;
    const session = await hesabe.checkout.create({
      amount,
      orderReferenceNumber: reference,
      // 0 leaves the method to the app: one session serves KNET, cards and Apple Pay.
      paymentType: 0,
      responseUrl: RETURN_URL,
      failureUrl: RETURN_URL,
      // With a customer and saveCard, Hesabe's card form offers to save the card.
      ...(saveCard === true ? { saveCard: true, customerId: await customerId() } : {}),
    });
    // `data` is what the SDK takes. It opens this one payment and nothing else. The
    // rest names the payment in the app when it ends without a transaction.
    return { data: session.data, token: session.token, reference, amount };
  },

  // The app says a payment ended. The server asks Hesabe itself before it releases
  // anything: what the app reports travelled through the customer's device.
  "POST /confirm": async ({ token }) => {
    if (typeof token !== "string" || !/^[0-9A-Za-z]+$/.test(token)) {
      throw new BadRequest("token is required");
    }
    try {
      const transaction = await hesabe.transactions.retrieve(token);
      // `transaction` is Hesabe's whole record. The app shows it beside the SDK's own.
      return { paid: isSuccessful(transaction), status: transaction.status, transaction };
    } catch (error) {
      // A session nobody has paid has no transaction, and Hesabe says "not found".
      if (error instanceof HesabeError && /not found/i.test(error.message)) {
        return { paid: false, status: "NOT_FOUND" };
      }
      throw error;
    }
  },

  // ---------------------------------------------------------------- saved cards
  // A session that saves a card and charges nothing: amount 0.000 with the customer.
  // The SDK shows Hesabe's card form for it and reports `.cardSaved`.
  "POST /cards/session": async () => {
    const reference = `DEMO-CARD-${Date.now()}`;
    const session = await hesabe.checkout.verifyCard({
      customerId: await customerId(),
      orderReferenceNumber: reference,
      responseUrl: RETURN_URL,
      failureUrl: RETURN_URL,
    });
    return { data: session.data, token: session.token, reference, amount: "0.000" };
  },

  // The customer's saved cards, as Hesabe lists them. The SDK's `HesabeSavedCard`
  // decodes each entry unchanged.
  "GET /cards": async () => ({ cards: (await savedCards()).cards }),

  // Charges a saved card. No page and no 3-D Secure: Hesabe authenticated the card
  // when it was saved. The answer is Hesabe's own, so this is already confirmed.
  "POST /cards/charge": async ({ cardId, quantity }) => {
    const amount = amountFor(quantity);
    const customer = await existingCustomerId();
    if (!Number.isInteger(cardId) || !customer) throw new BadRequest("this card is not saved");
    const reference = `DEMO-${Date.now()}`;
    try {
      // With the customer on the charge, Hesabe refuses a card saved by anyone else.
      // Never sent twice: Hesabe has no idempotency keys, so a retry is a second charge.
      const payment = await hesabe.cards.charge({
        cardId,
        customerId: customer,
        amount,
        orderReference: reference,
      });
      return {
        paid: isSuccessful(payment),
        status: payment.resultCode,
        amount: payment.amount,
        reference,
        token: payment.paymentToken,
        paymentId: text(payment.paymentId),
        transactionId: text(payment.transactionId),
        trackId: text(payment.trackID),
        auth: text(payment.auth),
        paidOn: payment.paidOn,
        // Hesabe's whole answer, for the app's result screen.
        raw: JSON.stringify(payment, null, 2),
      };
    } catch (error) {
      // The issuer said no. That is an answer, not a server error.
      if (error instanceof HesabeCardError) {
        return { paid: false, status: "DECLINED", amount, reference, message: error.message };
      }
      throw error;
    }
  },

  // Removes a saved card. Hesabe's call takes any card id of the merchant, so the
  // server checks that the card belongs to this customer first.
  "POST /cards/remove": async ({ cardId }) => {
    const { cards } = await savedCards();
    if (!cards.some((card) => card.card_id === cardId)) throw new BadRequest("this card is not saved");
    await hesabe.cards.remove(cardId);
    return { removed: true };
  },

  "GET /health": async () => ({ ok: true, environment: hesabe.environment }),
};

class BadRequest extends Error {}

// Hesabe sends ids as strings in some answers and as numbers in others.
const text = (value) => (value == null ? undefined : String(value));

createServer(async (req, res) => {
  const route = `${req.method} ${new URL(req.url, "http://localhost").pathname}`;
  const handler = routes[route];
  const send = (status, body) => {
    res.writeHead(status, { "Content-Type": "application/json" });
    res.end(JSON.stringify(body));
  };
  if (!handler) return send(404, { error: `no route for ${route}` });

  try {
    send(200, await handler(req.method === "POST" ? await readJson(req) : {}));
  } catch (error) {
    if (error instanceof BadRequest) return send(400, { error: error.message });
    if (error instanceof HesabeError) {
      console.error(`[hesabe] ${error.name}: ${error.message}`);
      return send(502, { error: error.message });
    }
    console.error(error);
    send(500, { error: "internal error" });
  }
}).listen(PORT, () => {
  console.log(`Hesabe demo backend on http://localhost:${PORT} (${hesabe.environment})`);
});

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  try {
    return chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {};
  } catch {
    throw new BadRequest("body is not valid JSON");
  }
}
