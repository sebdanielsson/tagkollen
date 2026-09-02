import SwiftUI
import TrafikverketKit

/// Vertical timeline of every stop with planned, estimated and actual times.
struct StopTimelineView: View {
    let journey: TrainJourney
    @Environment(StationDirectory.self) private var stations

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(journey.stops.enumerated()), id: \.element.id) { index, stop in
                StopRow(
                    stop: stop,
                    name: stations.name(stop.signature),
                    isFirst: index == 0,
                    isLast: index == journey.stops.count - 1,
                    isNext: journey.nextStop?.id == stop.id
                )
            }
        }
    }
}

private struct StopRow: View {
    let stop: TrainStop
    let name: String
    let isFirst: Bool
    let isLast: Bool
    let isNext: Bool
    @State private var expanded = false

    private var lineColor: Color {
        stop.hasPassed ? .secondary.opacity(0.5) : .accentColor
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            timeColumn
                .frame(width: 76, alignment: .leading)
            rail
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(isNext || isFirst || isLast ? .body.weight(.semibold) : .body)
                        .foregroundStyle(stop.isCanceled ? .secondary : .primary)
                        .strikethrough(stop.isCanceled, color: .red)
                    Spacer()
                    if let track = stop.track {
                        Text("Track \(track)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    DelayBadge(delay: stop.delay, canceled: stop.isCanceled, compact: true)
                    if stop.isPartlyCanceled {
                        Text("Partly canceled").font(.caption2).foregroundStyle(.orange)
                    }
                    if isNext {
                        Text("Next stop").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
                    }
                }
                if !stop.deviations.isEmpty || !stop.otherInformation.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(stop.deviations, id: \.self) { dev in
                            Label(dev.description ?? dev.code ?? "", systemImage: "exclamationmark.circle")
                                .labelStyle(.compactIcon)
                                .foregroundStyle(.orange)
                        }
                        if expanded {
                            ForEach(stop.otherInformation, id: \.self) { info in
                                Label(info.description ?? info.code ?? "", systemImage: "info.circle")
                                    .labelStyle(.compactIcon)
                                    .foregroundStyle(.secondary)
                            }
                        } else if !stop.otherInformation.isEmpty {
                            Button {
                                withAnimation(.snappy) { expanded = true }
                            } label: {
                                Text("\(stop.otherInformation.count) more")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
            }
            .padding(.bottom, isLast ? 0 : 14)
        }
        .contentShape(.rect)
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
        .accessibilityElement(children: .combine)
    }

    private var timeColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let arr = stop.arrival {
                timeBlock(label: "Arr", announcement: arr, showLabel: stop.departure != nil)
            }
            if let dep = stop.departure {
                timeBlock(label: "Dep", announcement: dep, showLabel: stop.arrival != nil)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Best-known time on top; the timetable time struck through beneath it when they differ.
    private func timeBlock(label: LocalizedStringKey, announcement: TrainAnnouncement, showLabel: Bool) -> some View {
        let planned = announcement.advertisedTimeAtLocation
        let known = announcement.timeAtLocation ?? announcement.estimatedTimeAtLocation
        let differs = known != nil && known != planned && !announcement.isCanceled
        let isEstimate = !announcement.hasDeparted && (announcement.estimatedTimeIsPreliminary ?? false)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            if showLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 0) {
                if differs, let known {
                    Text(Format.clock(known))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(DelayIndex.severity(delay: announcement.delay, canceled: false).color)
                        .italic(isEstimate)
                    Text(Format.clock(planned))
                        .font(.caption)
                        .strikethrough(color: .secondary)
                        .foregroundStyle(.secondary)
                } else {
                    Text(Format.clock(planned))
                        .font(.callout)
                        .strikethrough(announcement.isCanceled, color: .red)
                        .foregroundStyle(announcement.isCanceled ? .secondary : .primary)
                }
            }
        }
    }

    private var rail: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? Color.clear : lineColor)
                .frame(width: 3, height: 8)
            ZStack {
                Circle()
                    .fill(stop.isCanceled ? Color.red.opacity(0.6) : (stop.hasPassed ? Color.secondary : Color.accentColor))
                    .frame(width: isNext ? 14 : 10, height: isNext ? 14 : 10)
                if stop.hasPassed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 6, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            Rectangle()
                .fill(isLast ? Color.clear : lineColor)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 14)
    }
}

/// Icon and text on one line with tight spacing, unlike the default label style's aligned icon column.
private struct CompactIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

private extension LabelStyle where Self == CompactIconLabelStyle {
    static var compactIcon: CompactIconLabelStyle {
        CompactIconLabelStyle()
    }
}
