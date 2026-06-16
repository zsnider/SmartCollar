import Foundation
import Combine

@MainActor
final class WebSocketManager: ObservableObject {
    static let shared = WebSocketManager()

    private var task: URLSessionWebSocketTask?
    private var pingTask: Task<Void, Never>?

    var onLeaderboardUpdate: ((LeaderboardResponse) -> Void)?

    func connect(baseURL: String = "ws://localhost:3000") {
        guard let url = URL(string: "\(baseURL)/ws") else { return }
        task = URLSession.shared.webSocketTask(with: url)
        task?.resume()
        listenForMessages()
        startPing()
    }

    func disconnect() {
        pingTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func subscribeToLeaderboard(locationId: String, metric: String, period: String) {
        send([
            "type": "subscribe_leaderboard",
            "locationId": locationId,
            "metric": metric,
            "period": period,
        ])
    }

    func unsubscribe() {
        send(["type": "unsubscribe"])
    }

    // MARK: - Private

    private func send(_ dict: [String: String]) {
        guard let data = try? JSONEncoder().encode(dict),
              let str = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(str)) { error in
            if let error { print("WS send error: \(error)") }
        }
    }

    private func listenForMessages() {
        task?.receive { [weak self] result in
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self?.handleMessage(text)
                }
                self?.listenForMessages() // re-arm
            case .failure(let error):
                print("WS receive error: \(error)")
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        if let envelope = try? JSONDecoder().decode([String: String].self, from: data),
           envelope["type"] == "leaderboard_update" || envelope["type"] == "leaderboard_snapshot",
           let response = try? decoder.decode(LeaderboardResponse.self, from: data) {
            Task { @MainActor [weak self] in
                self?.onLeaderboardUpdate?(response)
            }
        }
    }

    private func startPing() {
        pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                task?.sendPing { _ in }
            }
        }
    }
}
