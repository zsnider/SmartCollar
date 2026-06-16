import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isAuthenticated = false

    private let api = APIClient.shared

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            _ = try await api.login(email: email, password: password)
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func register(email: String, displayName: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            _ = try await api.register(email: email, displayName: displayName, password: password)
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func logout() {
        api.logout()
        isAuthenticated = false
    }
}
