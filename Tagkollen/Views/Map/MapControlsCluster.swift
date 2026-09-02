import MapKit
import SwiftUI

/// Bottom-right map controls on iPhone, Apple Maps style: map type and user location.
struct MapControlsCluster: View {
    @Binding var camera: MapCameraPosition
    let scope: Namespace.ID
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 0) {
                Menu {
                    Picker("Map type", selection: $settings.mapAppearance) {
                        Label("Standard", systemImage: "map").tag(AppSettings.MapAppearance.standard)
                        Label("Muted", systemImage: "map.fill").tag(AppSettings.MapAppearance.muted)
                        Label("Satellite", systemImage: "globe.europe.africa.fill").tag(AppSettings.MapAppearance.hybrid)
                    }
                    Divider()
                    Toggle("Show train numbers", isOn: $settings.showTrainLabels)
                    Toggle("Colour trains by delay", isOn: $settings.colorMarkersByDelay)
                    Button("Whole country", systemImage: "arrow.down.left.and.arrow.up.right") {
                        withAnimation(.smooth) { camera = .region(MapScreen.swedenRegion) }
                    }
                } label: {
                    Image(systemName: "map")
                        .font(.body.weight(.medium))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel(Text("Map type"))
                Divider().frame(width: 28)
                MapUserLocationButton(scope: scope)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        }
    }
}
