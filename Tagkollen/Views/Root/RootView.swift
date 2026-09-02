import SwiftUI

/// Top-level tab structure. On iPad the tab bar adapts to a sidebar and each tab uses the
/// full window with split navigation.
struct RootView: View {
    @State private var navigation = AppNavigation()
    @Environment(APIKeyStore.self) private var keyStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showOnboarding = false

    var body: some View {
        if sizeClass == .regular {
            tabs
        } else {
            phone
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
    /// `-tab map|saved|search` selects a tab and `-train <number>` opens a train at launch. Debug builds only; used by
    /// Scripts/simulator.sh.
    private func applyDebugLaunchArguments() {
        #if DEBUG
            if let ident = UserDefaults.standard.string(forKey: "train"), !ident.isEmpty {
                navigation.showOnMap(TrainKey(id: ident) ?? .today(ident))
            }
            switch UserDefaults.standard.string(forKey: "tab") {
            case "saved", "favorites": navigation.selectedTab = .favorites
            case "search": navigation.selectedTab = .search
            case "map": navigation.selectedTab = .map
            default: break
            }
        #endif
    }
}

#Preview {
    RootView()
        .environment(AppDependencies())
}
