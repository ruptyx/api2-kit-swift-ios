import HesabeUI
import SwiftUI

/// The customer's saved cards: pay with one, remove one, add one. The cards belong to
/// your server, so every action here is a request to it, and each shows a spinner on
/// the row it was asked from.
@MainActor
struct SavedCardsSection: View {
    /// `nil` until the server has answered.
    let cards: [HesabeSavedCard]?
    /// Why the list could not be read.
    let loadError: String?
    /// The card being charged or removed.
    let busyCard: HesabeSavedCard.ID?
    /// True while the session for a new card is being created.
    let isAdding: Bool
    let onPay: (HesabeSavedCard) -> Void
    let onRemove: (HesabeSavedCard) -> Void
    let onAdd: () -> Void
    let onReload: () -> Void

    /// Editing swaps "tap to pay" for a Remove button on every card.
    @State private var isEditing = false

    var body: some View {
        Section {
            if let cards {
                if cards.isEmpty {
                    Text("No saved cards yet. Add one to pay without typing it again.")
                        .foregroundStyle(Color.secondary)
                }
                ForEach(cards) { card in
                    row(for: card)
                        .swipeActions {
                            Button("Remove") { onRemove(card) }
                                .tint(.red)
                        }
                }
            } else if let loadError {
                Text(loadError)
                    .foregroundStyle(Color.secondary)
                Button("Try again", action: onReload)
            } else {
                LabeledContent("Loading your cards…") { ProgressView() }
            }
            PayButton(title: "Add a card", isBusy: isAdding, action: onAdd)
        } header: {
            HStack {
                Text("Saved cards")
                Spacer()
                if cards?.isEmpty == false {
                    Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
                        .font(.footnote)
                        .textCase(nil)
                }
            }
        } footer: {
            Text("Tap a card to pay with it. The server charges it: no page, no 3-D Secure.")
        }
    }

    @ViewBuilder
    private func row(for card: HesabeSavedCard) -> some View {
        if isEditing {
            HStack {
                SavedCardRow(card: card)
                Spacer()
                if busyCard == card.id {
                    ProgressView()
                } else {
                    Button("Remove", role: .destructive) { onRemove(card) }
                        .buttonStyle(.borderless)
                }
            }
        } else {
            Button {
                onPay(card)
            } label: {
                HStack {
                    SavedCardRow(card: card)
                    Spacer()
                    if busyCard == card.id {
                        ProgressView()
                    }
                }
            }
        }
    }
}

/// One saved card: Hesabe's card logo, the scheme and the last four digits, then the
/// expiry.
@MainActor
private struct SavedCardRow: View {
    let card: HesabeSavedCard

    var body: some View {
        HStack(spacing: 12) {
            HesabeMethodLogo(.card)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.displayName)
                    .foregroundStyle(Color.primary)
                Text("Expires \(card.expiry)")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}
