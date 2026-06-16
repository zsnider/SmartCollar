import SwiftUI
import MapKit

@MainActor
final class MapViewModel: ObservableObject {
    @Published var locations: [Location] = []
    @Published var searchText = ""
    @Published var suggestions: [Location] = []
    @Published var showSuggestions = false
    @Published var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 32.7157, longitude: -117.1611),
        span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
    ))

    private let api = APIClient.shared
    private let locationManager = LocationManager.shared

    func load() async {
        locationManager.requestPermission()
        locationManager.startMonitoring()
        locations = (try? await api.fetchLocations()) ?? []
    }

    func updateSearch(_ text: String) {
        searchText = text
        if text.isEmpty {
            suggestions = []
            showSuggestions = false
        } else {
            suggestions = locations.filter {
                $0.name.localizedCaseInsensitiveContains(text)
            }
            showSuggestions = true
        }
    }

    func selectSuggestion(_ location: Location) {
        searchText = location.name
        suggestions = []
        showSuggestions = false
        // Fly to that location on the map
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng),
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        ))
    }

    func clearSearch() {
        searchText = ""
        suggestions = []
        showSuggestions = false
    }

    func centerOnUser() {
        guard let loc = locationManager.currentLocation else { return }
        cameraPosition = .region(MKCoordinateRegion(
            center: loc.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        ))
    }

    var visibleLocations: [Location] {
        if searchText.isEmpty { return locations }
        return locations.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

struct MapView: View {
    @StateObject private var vm = MapViewModel()
    @State private var selectedLocation: Location?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Map
                Map(position: $vm.cameraPosition, selection: $selectedLocation) {
                    ForEach(vm.visibleLocations) { location in
                        Annotation(
                            location.name,
                            coordinate: CLLocationCoordinate2D(
                                latitude: location.lat,
                                longitude: location.lng
                            ),
                            anchor: .bottom
                        ) {
                            LocationPin(
                                location: location,
                                isSelected: selectedLocation?.id == location.id
                            )
                            .onTapGesture {
                                selectedLocation = location
                            }
                        }
                    }
                    UserAnnotation()
                }
                .mapControls { MapCompass(); MapScaleView() }
                .ignoresSafeArea(edges: .bottom)
                .onTapGesture {
                    // Dismiss search when tapping map
                    searchFocused = false
                    vm.showSuggestions = false
                }

                // Search + suggestions overlay
                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search dog parks...", text: $vm.searchText)
                            .focused($searchFocused)
                            .onChange(of: vm.searchText) { _, new in
                                vm.updateSearch(new)
                            }
                            .submitLabel(.search)
                            .onSubmit { searchFocused = false }
                        if !vm.searchText.isEmpty {
                            Button {
                                vm.clearSearch()
                                searchFocused = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Suggestions dropdown
                    if vm.showSuggestions && !vm.suggestions.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(vm.suggestions.prefix(6)) { location in
                                Button {
                                    vm.selectSuggestion(location)
                                    searchFocused = false
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: locationIcon(location.type))
                                            .foregroundStyle(.orange)
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(location.name)
                                                .foregroundStyle(.primary)
                                                .font(.subheadline)
                                            Text(location.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                                .foregroundStyle(.secondary)
                                                .font(.caption)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.left")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                }
                                if location.id != vm.suggestions.prefix(6).last?.id {
                                    Divider().padding(.leading, 46)
                                }
                            }
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    }

                    Spacer()

                    // Recenter button
                    HStack {
                        Spacer()
                        Button { vm.centerOnUser() } label: {
                            Image(systemName: "location.fill")
                                .padding(12)
                                .background(.regularMaterial, in: Circle())
                        }
                        .padding(.trailing)
                        .padding(.bottom, 100)
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

    private func locationIcon(_ type: LocationType) -> String {
        switch type {
        case .dogPark: return "pawprint.fill"
        case .trail:   return "figure.hiking"
        case .beach:   return "beach.umbrella.fill"
        case .other:   return "mappin.circle.fill"
        }
    }
}

struct LocationPin: View {
    let location: Location
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.orange : Color.white)
                    .frame(width: 36, height: 36)
                    .shadow(radius: isSelected ? 4 : 2)
                Image(systemName: iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? .white : .orange)
            }
            if isSelected {
                Text(location.name)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.orange, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
        }
        .animation(.spring(duration: 0.2), value: isSelected)
    }

    private var iconName: String {
        switch location.type {
        case .dogPark: return "pawprint.fill"
        case .trail:   return "figure.hiking"
        case .beach:   return "beach.umbrella.fill"
        case .other:   return "mappin.circle.fill"
        }
    }
}
