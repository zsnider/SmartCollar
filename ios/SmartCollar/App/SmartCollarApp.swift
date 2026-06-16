import SwiftUI

@main
struct SmartCollarApp: App {
    @StateObject private var authVM = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            if authVM.isAuthenticated || APIClient.shared.isAuthenticated {
                MainTabView()
                    .environmentObject(authVM)
            } else {
                AuthView()
                    .environmentObject(authVM)
                    .onReceive(authVM.$isAuthenticated) { authenticated in
                        // Handled by the conditional above
                        _ = authenticated
                    }
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        TabView {
            DogListView()
                .tabItem { Label("My Dogs", systemImage: "pawprint.fill") }

            MapView()
                .tabItem { Label("Nearby", systemImage: "map.fill") }

            Text("Activity Feed — Coming Soon")
                .tabItem { Label("Activity", systemImage: "heart.fill") }

            ProfileView(onLogout: authVM.logout)
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
        .tint(.orange)
    }
}

struct ProfileView: View {
    let onLogout: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Log Out", role: .destructive) { onLogout() }
                }
            }
            .navigationTitle("Profile")
        }
    }
}
