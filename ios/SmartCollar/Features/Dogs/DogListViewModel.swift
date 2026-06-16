import Foundation

@MainActor
final class DogListViewModel: ObservableObject {
    @Published var dogs: [Dog] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = APIClient.shared

    func loadDogs() async {
        isLoading = true
        do {
            dogs = try await api.fetchDogs()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func addDog(name: String, breed: String?, weightLbs: Double?) async {
        do {
            let dog = try await api.createDog(name: name, breed: breed, weightLbs: weightLbs)
            dogs.append(dog)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
