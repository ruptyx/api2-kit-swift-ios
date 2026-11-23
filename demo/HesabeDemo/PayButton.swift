import SwiftUI

/// A row that starts something on a server and says so at once: the spinner is inside
/// the button from the tap, so the customer never wonders whether the tap worked.
///
/// The view that owns it disables it while anything is in flight, which is what keeps a
/// second tap from starting a second payment.
@MainActor
struct PayButton: View {
    let title: String
    /// One line under the title saying what the button does.
    var caption: String?
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let caption {
                        Text(caption)
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    }
                }
                Spacer()
                if isBusy {
                    ProgressView()
                }
            }
        }
    }
}
