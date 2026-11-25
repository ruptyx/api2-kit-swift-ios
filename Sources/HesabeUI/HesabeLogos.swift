#if canImport(UIKit)
import Hesabe
import SwiftUI
import UIKit

/// Hesabe's logos for payment methods, each on a white badge so it reads the same in
/// light and dark mode. The method list shows them, and your own screens can too.
///
/// A logo is fetched once from `PaymentMethod.logoURL` and kept while the app runs. The
/// request carries nothing about the payment or the customer.
@MainActor
public enum HesabeLogos {
    /// The size of a badge, in points.
    public static let badgeSize = CGSize(width: 46, height: 30)

    /// A clear image the size of a badge. It holds a logo's place in a row, so the
    /// names line up before the logos arrive.
    static let placeholder = UIGraphicsImageRenderer(size: badgeSize).image { _ in }

    private static var badges: [PaymentMethod: UIImage] = [:]
    private static var downloads: [PaymentMethod: Task<Data?, Never>] = [:]

    /// The method's logo on a badge. `nil` when Hesabe has no logo for the method or it
    /// could not be fetched: show the method's name alone. A fetch that failed is tried
    /// again the next time the logo is asked for.
    public static func badge(for method: PaymentMethod) async -> UIImage? {
        if let badge = badges[method] { return badge }

        // Two rows asking for the same logo share one download.
        let download: Task<Data?, Never>
        if let running = downloads[method] {
            download = running
        } else {
            download = Task { await data(for: method) }
            downloads[method] = download
        }
        let data = await download.value
        downloads[method] = nil

        // Another caller may have drawn the badge while this one waited.
        if let badge = badges[method] { return badge }
        guard let data, let logo = UIImage(data: data), logo.size.width > 0, logo.size.height > 0
        else { return nil }
        let badge = draw(logo)
        badges[method] = badge
        return badge
    }

    /// The badge when it has already been fetched.
    static func fetched(_ method: PaymentMethod) -> UIImage? {
        badges[method]
    }

    /// Starts fetching the logos of `methods`, so they are there when a list shows them.
    static func prefetch(_ methods: [PaymentMethod]) {
        for method in methods {
            Task { _ = await badge(for: method) }
        }
    }

    nonisolated private static func data(for method: PaymentMethod) async -> Data? {
        var request = URLRequest(url: method.logoURL)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }

    /// A white rounded tile with the logo fitted inside it. Hesabe's logos come in
    /// every size and shape, and several are dark artwork on a clear background.
    private static func draw(_ logo: UIImage) -> UIImage {
        let bounds = CGRect(origin: .zero, size: badgeSize)
        return UIGraphicsImageRenderer(size: badgeSize).image { _ in
            let tile = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 5)
            UIColor.white.setFill()
            tile.fill()
            UIColor(white: 0, alpha: 0.15).setStroke()
            tile.stroke()

            let room = bounds.insetBy(dx: 4, dy: 4)
            let scale = min(room.width / logo.size.width, room.height / logo.size.height)
            let size = CGSize(width: logo.size.width * scale, height: logo.size.height * scale)
            logo.draw(in: CGRect(
                x: room.midX - size.width / 2, y: room.midY - size.height / 2,
                width: size.width, height: size.height))
        }
    }
}

/// A payment method's logo for your own buttons and rows: the badge the method list
/// shows. It keeps the badge's room while the logo is fetched, and when Hesabe has none.
@MainActor
public struct HesabeMethodLogo: View {
    private let method: PaymentMethod
    @State private var badge: UIImage?

    public init(_ method: PaymentMethod) {
        self.method = method
    }

    public var body: some View {
        ZStack {
            if let badge {
                Image(uiImage: badge)
            }
        }
        .frame(width: HesabeLogos.badgeSize.width, height: HesabeLogos.badgeSize.height)
        .task(id: method) { badge = await HesabeLogos.badge(for: method) }
        // The method's name is beside it.
        .accessibilityHidden(true)
    }
}
#endif
