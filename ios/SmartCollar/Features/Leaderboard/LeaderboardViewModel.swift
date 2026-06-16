import Foundation

@MainActor
final class LeaderboardViewModel: ObservableObject {
    @Published var entries: [LeaderboardEntry] = []
    @Published var isLoading = false
    @Published var selectedMetric = "maxSpeedMph"
    @Published var selectedPeriod = "weekly"

    let metrics = ["totalSteps", "maxSpeedMph", "avgSpeedMph", "peakAccelG"]
    let periods = ["daily", "weekly", "alltime"]

    private let api = APIClient.shared
    private let ws = WebSocketManager.shared

    func load(locationId: String) async {
        isLoading = true
        do {
            let result = try await api.fetchLeaderboard(
                locationId: locationId,
                metric: selectedMetric,
                period: selectedPeriod
            )
            entries = result.entries
        } catch {
            print("Leaderboard load error: \(error)")
        }
        isLoading = false

        // Subscribe to live updates
        ws.onLeaderboardUpdate = { [weak self] response in
            guard let self,
                  response.metric == self.selectedMetric,
                  response.period == self.selectedPeriod else { return }
            self.entries = response.entries
        }
        ws.subscribeToLeaderboard(locationId: locationId, metric: selectedMetric, period: selectedPeriod)
    }

    func changeFilter(locationId: String) async {
        ws.unsubscribe()
        await load(locationId: locationId)
    }

    var metricLabel: String {
        switch selectedMetric {
        case "totalSteps": return "Most Steps"
        case "maxSpeedMph": return "Top Speed"
        case "avgSpeedMph": return "Avg Speed"
        case "peakAccelG": return "Peak Accel"
        default: return selectedMetric
        }
    }
}
