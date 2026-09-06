import SwiftUI

/// Map marker for a station: a coloured disc with a building icon, matching `TrainMarker`'s
/// selected/ambient sizing so the two marker types read as one visual language. Ambient stations
/// (not selected) are shown small; the selected station grows, like a selected train does.
struct StationMarker: View {
    /// The station's name, so VoiceOver can tell one dot from another.
    var name: String
    var isSelected = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.gradient)
                .frame(width: isSelected ? 28 : 16, height: isSelected ? 28 : 16)
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.9), lineWidth: isSelected ? 3 : 1.5)
                }
                .shadow(color: .black.opacity(0.25), radius: isSelected ? 6 : 1, y: 1)
            Image(systemName: "building.columns.fill")
                .font(.system(size: isSelected ? 13 : 8, weight: .semibold))
                .foregroundStyle(.white)
        }
        .animation(.snappy, value: isSelected)
        .accessibilityLabel(Text("Station \(name)"))
    }
}
