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
                .frame(width: 92, alignment: .leading)
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
                                .foregroundStyle(.orange)
                        }
                        if expanded {
                            ForEach(stop.otherInformation, id: \.self) { info in
                                Label(info.description ?? info.code ?? "", systemImage: "info.circle")
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
        VStack(alignment: .leading, spacing: 2) {
            if let arr = stop.arrival {
                timeLine(label: "Arr", announcement: arr)
            }
            if let dep = stop.departure {
                timeLine(label: "Dep", announcement: dep)
            }
        }
        .font(.callout)
        .monospacedDigit()
    }

    private func timeLine(label: LocalizedStringKey, announcement: TrainAnnouncement) -> some View {
        let planned = announcement.advertisedTimeAtLocation
        let known = announcement.timeAtLocation ?? announcement.estimatedTimeAtLocation
        let differs = known != nil && known != planned
        return HStack(spacing: 4) {
            if stop.arrival != nil, stop.departure != nil {
                Text(label).font(.caption2).foregroundStyle(.tertiary).frame(width: 24, alignment: .leading)
            }
            Text(Format.clock(planned))
                .strikethrough(announcement.isCanceled || differs, color: announcement.isCanceled ? .red : .secondary)
                .foregroundStyle(announcement.isCanceled || differs ? .secondary : .primary)
            if differs, !announcement.isCanceled, let known {
                Text(Format.clock(known))
                    .fontWeight(.semibold)
                    .foregroundStyle(DelayIndex.severity(delay: announcement.delay, canceled: false).color)
                    .opacity(announcement.hasDeparted ? 1 : 0.9)
                    .italic(!announcement.hasDeparted && (announcement.estimatedTimeIsPreliminary ?? false))
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
