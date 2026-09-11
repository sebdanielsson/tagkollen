import SwiftData
import SwiftUI

/// Top-level tab structure. On iPad the tab bar adapts to a sidebar and each tab uses the
/// full window with split navigation.
struct RootView: View {
    @State private var navigation = AppNavigation()
    @Environment(AppDependencies.self) private var deps
    @Environment(APIKeyStore.self) private var keyStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showOnboarding = false

    var body: some View {
        Group {
            if sizeClass == .regular {
                tabs
            } else {
                phone
            }
        }
        .onChange(of: deps.pendingOpenURL) { _, url in
            guard let url else { return }
            navigation.handle(url)
            deps.pendingOpenURL = nil
        }
    }

    /// iPhone: Apple Maps-like single screen. The bottom card carries search and saved trains.
    @ViewBuilder
    private var phone: some View {
        if keyStore.hasKey {
            MapScreen()
                .environment(navigation)
                .onOpenURL { navigation.handle($0) }
                .onAppear { applyDebugLaunchArguments() }
        } else {
            NavigationStack {
                APIKeyOnboardingView()
            }
        }
    }

    /// iPad: adaptive tab bar / sidebar with full-width screens.
    private var tabs: some View {
        @Bindable var navigation = navigation
        return TabView(selection: $navigation.selectedTab) {
            Tab("Map", systemImage: "map", value: AppNavigation.Tab.map) {
                MapScreen()
            }
            Tab("Saved", systemImage: "star", value: AppNavigation.Tab.favorites) {
                FavoritesScreen()
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppNavigation.Tab.search, role: .search) {
                SearchScreen()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(navigation)
        .onAppear {
            showOnboarding = !keyStore.hasKey
            applyDebugLaunchArguments()
        }
        .onOpenURL { navigation.handle($0) }
        .onChange(of: keyStore.hasKey) { _, hasKey in
            if hasKey {
                showOnboarding = false
            }
        }
        .sheet(isPresented: $showOnboarding) {
            NavigationStack {
                APIKeyOnboardingView()
            }
            .interactiveDismissDisabled(!keyStore.hasKey)
        }
    }
}

extension RootView {
    /// `-tab map|saved|search` selects a tab, `-train <number>` opens a train at launch,
    /// `-station <signature>` opens a departure board and `-save <number>[,<number>…]` pins trains
    /// so the Saved sections have something to show. Debug builds only; used by
    /// Scripts/simulator.sh and Scripts/screenshots.sh.
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
            switch UserDefaults.standard.string(forKey: "tab") {
            case "saved", "favorites": navigation.selectedTab = .favorites
            case "search": navigation.selectedTab = .search
            case "map": navigation.selectedTab = .map
            default: break
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
            let pinned = Set(((try? modelContext.fetch(FetchDescriptor<FavoriteTrain>())) ?? []).map(\.id))
            for key in keys where !pinned.contains(key.id) {
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
