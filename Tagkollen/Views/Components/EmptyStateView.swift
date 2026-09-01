import SwiftUI

/// Shared empty / error state with an optional action.
struct EmptyStateView: View {
    var systemImage: String
    var title: LocalizedStringKey
    var message: LocalizedStringKey?
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message {
                Text(message)
            }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassProminent)
            }
        }
    }
}
