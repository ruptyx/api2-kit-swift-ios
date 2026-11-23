@_exported import Hesabe
import Foundation

/// The few words the SDK shows itself. English or Arabic by the device language;
/// replace any of them to match your app.
public struct HesabeStrings: Sendable, Hashable {
    /// The language Hesabe's card form is asked for: `en` or `ar`.
    public var languageCode: String
    public var cancel: String
    public var chooseMethod: String
    /// The title above the card form when the session saves a card and charges nothing.
    public var addCard: String
    /// Under the loader while the session is read, before any payment page opens.
    public var preparing: String
    /// Under the loader while one method's page opens. `%@` is the method's name:
    /// "Connecting to KNET…".
    public var connecting: String
    /// Under the loader while Hesabe's embedded card form opens.
    public var openingCardForm: String
    /// Under the loader while Hesabe's own page, with every method, opens.
    public var openingPaymentPage: String
    public var confirming: String
    public var processing: String
    public var paid: String
    public var cardSaved: String
    public var notPaid: String
    public var pending: String
    public var unconfirmed: String
    public var tryAgain: String

    public init(
        languageCode: String, cancel: String, chooseMethod: String, addCard: String,
        preparing: String, connecting: String, openingCardForm: String, openingPaymentPage: String,
        confirming: String, processing: String, paid: String, cardSaved: String,
        notPaid: String, pending: String, unconfirmed: String, tryAgain: String
    ) {
        self.languageCode = languageCode
        self.cancel = cancel
        self.chooseMethod = chooseMethod
        self.addCard = addCard
        self.preparing = preparing
        self.connecting = connecting
        self.openingCardForm = openingCardForm
        self.openingPaymentPage = openingPaymentPage
        self.confirming = confirming
        self.processing = processing
        self.paid = paid
        self.cardSaved = cardSaved
        self.notPaid = notPaid
        self.pending = pending
        self.unconfirmed = unconfirmed
        self.tryAgain = tryAgain
    }

    public static let english = HesabeStrings(
        languageCode: "en",
        cancel: "Cancel",
        chooseMethod: "Pay with",
        addCard: "Add a card",
        preparing: "Preparing your payment…",
        connecting: "Connecting to %@…",
        openingCardForm: "Opening secure card form…",
        openingPaymentPage: "Opening the payment page…",
        confirming: "Confirming your payment…",
        processing: "Processing",
        paid: "Payment complete",
        cardSaved: "Card saved",
        notPaid: "Payment not completed",
        pending: "Your payment is being processed",
        unconfirmed: "We couldn't confirm this payment yet",
        tryAgain: "Try again"
    )

    public static let arabic = HesabeStrings(
        languageCode: "ar",
        cancel: "إلغاء",
        chooseMethod: "ادفع بواسطة",
        addCard: "إضافة بطاقة",
        preparing: "جارٍ تجهيز الدفع…",
        connecting: "جارٍ الاتصال بـ %@…",
        openingCardForm: "جارٍ فتح نموذج البطاقة الآمن…",
        openingPaymentPage: "جارٍ فتح صفحة الدفع…",
        confirming: "جارٍ تأكيد الدفع…",
        processing: "جارٍ المعالجة",
        paid: "تم الدفع",
        cardSaved: "تم حفظ البطاقة",
        notPaid: "لم يكتمل الدفع",
        pending: "عملية الدفع قيد المعالجة",
        unconfirmed: "تعذّر تأكيد الدفع حتى الآن",
        tryAgain: "أعد المحاولة"
    )

    /// Arabic when the device's first language is Arabic, English otherwise.
    public static var automatic: HesabeStrings {
        Locale.preferredLanguages.first?.hasPrefix("ar") == true ? .arabic : .english
    }

    /// The line under the loader while a payment page opens.
    ///
    /// - Parameters:
    ///   - method: the method whose page opens, `nil` for Hesabe's own page.
    ///   - inCardForm: `true` when the page is Hesabe's embedded card form.
    func opening(_ method: PaymentMethod?, inCardForm: Bool) -> String {
        if inCardForm { return openingCardForm }
        guard let method else { return openingPaymentPage }
        return connecting.replacingOccurrences(of: "%@", with: method.displayName)
    }

    /// The line shown for a settled payment, and whether it reads as a success.
    func summary(of result: PaymentResult) -> (succeeded: Bool, message: String)? {
        switch result {
        case .paid: return (true, paid)
        case .cardSaved: return (true, cardSaved)
        case .failed: return (false, notPaid)
        case .pending: return (false, pending)
        case .unconfirmed: return (false, unconfirmed)
        case .canceled, .notStarted: return nil
        }
    }
}
