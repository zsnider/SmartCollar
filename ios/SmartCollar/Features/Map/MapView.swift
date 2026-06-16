import SwiftUI
import MapKit

@MainActor
final class MapViewModel: ObservableObject {
    @Published var locations: [Location] = []
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    private let api = APIClient.shared
    private let locationManager = LocationManager.shared

    func load() async {
        if let loc = locationManager.currentLocation {
            region = MKCoordinateRegion(
                center: loc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            locations = (try? await api.fetchNearbyLocations(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude)) ?? []
        } else {
            locations = (try? await api.fetchLocations()) ?? []
        }
    }
}

struct MapView: View {
    @StateObject private var vm = MapViewModel()
    @State private var selectedLocation: Location?

    var body: some View {
        NavigationStack {
            Map(coordinateRegion: $vm.region, annotationItems: vm.locations) { location in
                MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng)) {
                    Button {
                        selectedLocation = location
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: location.type == .dogPark ? "pawprint.circle.fill" : "map.circle.fill")
                                .font(.title)
                                .foregroundStyle(location.isVerified ? .orange : .gray)
                                .background(Circle().fill(.white).padding(-2))
                            Text(location.name)
                                .font(.caption2)
                                .padding(3)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
            .navigationTitle("Nearby")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedLocation) { location in
                LeaderboardView(location: location)
            }
            .task { await vm.load() }
        }
    }
}
