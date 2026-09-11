import SwiftUI

/// Lets the user paste their own Trafikverket API key.
struct APIKeyView: View {
    @Environment(APIKeyStore.self) private var keyStore
    @Environment(LiveTrainStore.self) private var live
    @Environment(StationDirectory.self) private var stations
    @State private var draft = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                TextField("Paste your API key", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .submitLabel(.done)
                    .onSubmit(save)
            } header: {
                Text("Your key")
            } footer: {
                Text("Stored in the Keychain on this device only. Leave empty to use the key built into the app, if any.")
            }

            Section {
                Button("Save", action: save)
                    .disabled(draft.trimmingCharacters(in: .whitespaces) == (keyStore.source == .userProvided ? keyStore.key ?? "" : ""))
                if keyStore.source == .userProvided {
                    Button("Remove my key", role: .destructive) {
                        draft = ""
                        save()
                    }
                }
            }

            Section {
                Link(destination: keyStore.registrationURL) {
                    Label("Get a free key at data.trafikverket.se", systemImage: "arrow.up.right.square")
                }
            } footer: {
                Text("Create an account, then create an API key under \"Mina sidor\". The key is free and the data is licensed CC0.")
            }
        }
        .navigationTitle("API key")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if keyStore.source == .userProvided {
                draft = keyStore.key ?? ""
            }
        }
        .sensoryFeedback(.success, trigger: saved)
    }

    private func save() {
        keyStore.setUserKey(draft)
        saved.toggle()
        live.restart()
        Task { await stations.refresh() }
    }
}
