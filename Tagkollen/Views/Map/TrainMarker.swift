import SwiftUI

/// Map marker: a coloured disc with a direction chevron and the train number.
struct TrainMarker: View {
    let train: LiveTrain
    let severity: DelayIndex.Severity
    let isSelected: Bool
    let showLabel: Bool

    private var color: Color {
        train.isActive ? severity.markerColor : .gray
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if let bearing = train.bearing, (train.speed ?? 0) > 3 {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: isSelected ? 13 : 10, weight: .bold))
                        .foregroundStyle(color)
                        .rotationEffect(.degrees(Double(bearing)))
                        .offset(y: isSelected ? -19 : -15)
                }
                Circle()
                    .fill(color.gradient)
                    .frame(width: isSelected ? 28 : 20, height: isSelected ? 28 : 20)
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.9), lineWidth: isSelected ? 3 : 2)
                    }
                    .shadow(color: .black.opacity(0.25), radius: isSelected ? 6 : 2, y: 1)
                Image(systemName: "train.side.front.car")
                    .font(.system(size: isSelected ? 13 : 9, weight: .semibold))
                    .foregroundStyle(.white)
            }
            if showLabel || isSelected {
                Text(train.displayNumber)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .glassEffect(.regular, in: .capsule)
            }
        }
        .opacity(train.isStale ? 0.55 : 1)
        .animation(.snappy, value: isSelected)
        .accessibilityLabel(Text("Train \(train.displayNumber)"))
    }
}
