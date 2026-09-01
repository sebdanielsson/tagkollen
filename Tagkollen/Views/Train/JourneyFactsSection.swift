import SwiftUI

/// Supplementary facts: operator links, services on board, operational identifiers.
struct JourneyFactsSection: View {
    let journey: TrainJourney

    var body: some View {
        Section("Details") {
            if let type = journey.typeOfTraffic {
                LabeledContent("Type of traffic", value: type)
            }
            if let owner = journey.informationOwner {
                LabeledContent("Information owner", value: owner)
            }
            if let otn = journey.operationalTrainNumber {
                LabeledContent("Operational train number", value: otn)
            }
            if !journey.services.isEmpty {
                LabeledContent("On board") {
                    Text(journey.services.compactMap(\.description).joined(separator: ", "))
                        .multilineTextAlignment(.trailing)
                }
            }
            if let url = journey.webLink {
                Link(destination: url) {
                    Label(journey.webLinkName ?? url.host() ?? String(localized: "Operator website"), systemImage: "safari")
                }
            }
        }
    }
}
