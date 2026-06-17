import Foundation

@MainActor
final class DogDetailViewModel: ObservableObject {
    @Published var stats: DogStats?
    @Published var sessions: [Session] = []
    @Published var collars: [Collar] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    let dog: Dog
    private let api = APIClient.shared

    init(dog: Dog) {
        self.dog = dog
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let statsResult = api.fetchDogStats(dogId: dog.id)
        async let sessionsResult = api.fetchSessionHistory(dogId: dog.id)
        async let collarsResult = api.fetchCollars(dogId: dog.id)

        do {
            stats = try await statsResult
        } catch {
            errorMessage = "Could not load stats"
        }
        sessions = (try? await sessionsResult) ?? []
        collars = (try? await collarsResult) ?? []
    }

    func removeCollar(_ collar: Collar) async {
        do {
            // APIClient doesn't have deleteCollar yet — call directly
            let _: EmptyDecodable = try await api.request(
                "/dogs/\(dog.id)/collars/\(collar.id)",
                method: "DELETE"
            )
            collars.removeAll { $0.id == collar.id }
        } catch {
            errorMessage = "Could not remove collar"
        }
    }
}

private struct EmptyDecodable: Decodable {}
