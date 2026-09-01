import SwiftUI

/// Top-level tab structure. On iPad the tab bar adapts to a sidebar and each tab uses the
/// full window with split navigation.
struct RootView: View {
    @State private var navigation = AppNavigation()
    @Environment(APIKeyStore.self) private var keyStore
    @State private var showOnboarding = false

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.selectedTab) {
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
        .onAppear { showOnboarding = !keyStore.hasKey }
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

#Preview {
    RootView()
        .environment(AppDependencies())
}
