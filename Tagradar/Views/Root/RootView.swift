import SwiftData
import SwiftUI

/// The app is one map. `MapScreen` decides how to lay itself out for the size class it is given:
/// a bottom card on iPhone, a sidebar and an inspector around the map on iPad. Keeping that
/// decision inside `MapScreen` means a size-class change never rebuilds it.
struct RootView: View {
    @State private var navigation = AppNavigation()
    /// Owned here so the map's camera, selection and card trail are independent of any view
    /// being rebuilt — see `MapState`.
    @State private var mapState = MapState()
    @Environment(AppDependencies.self) private var deps
    @Environment(APIKeyStore.self) private var keyStore
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if keyStore.hasKey {
                MapScreen()
            } else {
                NavigationStack {
                    APIKeyOnboardingView()
                }
            }
        }
        .environment(navigation)
        .environment(mapState)
        .onOpenURL { navigation.handle($0) }
        .onAppear { applyDebugLaunchArguments() }
        .onChange(of: deps.pendingOpenURL) { _, url in
            guard let url else { return }
            navigation.handle(url)
            deps.pendingOpenURL = nil
        }
    }
}

extension RootView {
    /// `-train <number>` opens a train at launch, `-station <signature>` opens a departure board
    /// and `-save <number>[,<number>…]` pins trains so the Saved section has something to show.
    /// Debug builds only; used by Scripts/simulator.sh and Scripts/screenshots.sh.
    private func applyDebugLaunchArguments() {
        #if DEBUG
            seedDebugFavorites()
            if let ident = UserDefaults.standard.string(forKey: "train"), !ident.isEmpty {
                navigation.showOnMap(TrainKey(id: ident) ?? .today(ident))
            }
            // The same route a widget deep link takes, minus the confirmation alert `simctl openurl`
            // puts in front of a custom scheme.
            if let signature = UserDefaults.standard.string(forKey: "station"), !signature.isEmpty {
                navigation.showStation(signature)
            }
        #endif
    }

    /// Pins the runs named by `-save`, each `<number>` (today) or `<number>@<yyyy-MM-dd>`. The rows
    /// fill themselves in from the API the same way a starred train does, so nothing is faked here.
    private func seedDebugFavorites() {
        #if DEBUG
            guard let raw = UserDefaults.standard.string(forKey: "save"), !raw.isEmpty else { return }
            let keys = raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { TrainKey(id: $0) ?? .today($0) }
            var pinned = Set(((try? modelContext.fetch(FetchDescriptor<FavoriteTrain>())) ?? []).map(\.id))
            for key in keys where pinned.insert(key.id).inserted {
                modelContext.insert(FavoriteTrain(key: key, journey: nil))
            }
            try? modelContext.save()
        #endif
    }
}

#Preview {
    RootView()
        .environment(AppDependencies())
}
