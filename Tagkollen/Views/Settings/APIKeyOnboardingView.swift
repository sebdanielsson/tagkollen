import SwiftUI

/// First-launch screen when no API key is available.
struct APIKeyOnboardingView: View {
    @Environment(APIKeyStore.self) private var keyStore
    @Environment(LiveTrainStore.self) private var live
    @Environment(StationDirectory.self) private var stations
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)
            Image(systemName: "train.side.front.car")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.breathe)
            VStack(spacing: 8) {
                Text("Welcome to Tågkollen")
                    .font(.largeTitle.bold())
                Text("Live positions and timetables for every train in Sweden, straight from Trafikverket's open data.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 10) {
                Text("Tågkollen needs a free Trafikverket API key.")
                    .font(.headline)
                Text("1. Create an account at data.trafikverket.se\n2. Create an API key under \"Mina sidor\"\n3. Paste it below")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("API key", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .submitLabel(.go)
                    .onSubmit(save)
            }
            .padding()
            .background(.background.secondary, in: .rect(cornerRadius: 16))
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button(action: save) {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)

                Link(destination: keyStore.registrationURL) {
                    Text("Get a key at data.trafikverket.se").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle("Get started")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        keyStore.setUserKey(draft)
        live.restart()
        Task { await stations.refresh() }
    }
}
