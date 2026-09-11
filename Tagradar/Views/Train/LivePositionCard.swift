import SwiftUI

/// The train's latest GPS report: speed, heading and how old the fix is.
struct LivePositionCard: View {
    let train: LiveTrain

    var body: some View {
        HStack(spacing: 0) {
            stat(value: Format.speed(train.speed) ?? "–", label: "Speed", icon: "speedometer")
            Divider().frame(height: 28)
            stat(value: Format.compass(train.bearing) ?? "–", label: "Heading", icon: "location.north.line")
            Divider().frame(height: 28)
            stat(value: train.timestamp.map { Format.relative($0) } ?? "–", label: "Position", icon: "dot.radiowaves.left.and.right")
        }
        .padding(.vertical, 6)
    }

    private func stat(value: String, label: LocalizedStringKey, icon: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        }
        .frame(maxWidth: .infinity)
    }
}
