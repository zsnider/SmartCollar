import SwiftUI

struct LeaderboardView: View {
    let location: Location

    @StateObject private var vm = LeaderboardViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.metrics, id: \.self) { metric in
                        FilterChip(
                            label: metricLabel(metric),
                            isSelected: vm.selectedMetric == metric
                        ) {
                            vm.selectedMetric = metric
                            Task { await vm.changeFilter(locationId: location.id) }
                        }
                    }
                    Divider().frame(height: 24)
                    ForEach(vm.periods, id: \.self) { period in
                        FilterChip(
                            label: period.capitalized,
                            isSelected: vm.selectedPeriod == period
                        ) {
                            vm.selectedPeriod = period
                            Task { await vm.changeFilter(locationId: location.id) }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)

            if vm.isLoading && vm.entries.isEmpty {
                Spacer()
                ProgressView("Loading leaderboard...")
                Spacer()
            } else if vm.entries.isEmpty {
                ContentUnavailableView(
                    "No Data Yet",
                    systemImage: "trophy",
                    description: Text("Be the first to set a record at \(location.name)!")
                )
            } else {
                List(vm.entries) { entry in
                    LeaderboardRowView(entry: entry, metric: vm.selectedMetric)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(location.name)
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.load(locationId: location.id) }
    }

    private func metricLabel(_ metric: String) -> String {
        switch metric {
        case "totalSteps": return "Steps"
        case "maxSpeedMph": return "Top Speed"
        case "avgSpeedMph": return "Avg Speed"
        case "peakAccelG": return "Accel"
        default: return metric
        }
    }
}

struct LeaderboardRowView: View {
    let entry: LeaderboardEntry
    let metric: String

    var body: some View {
        HStack(spacing: 14) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(rankColor)
                    .frame(width: 36, height: 36)
                Text("\(entry.rank)")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.dogName).font(.headline)
                Text(entry.ownerName).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Text(formattedValue)
                .font(.headline)
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 4)
    }

    private var rankColor: Color {
        switch entry.rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .brown
        default: return .orange.opacity(0.4)
        }
    }

    private var formattedValue: String {
        switch metric {
        case "totalSteps", "sessionCount":
            return "\(Int(entry.value))"
        case "maxSpeedMph", "avgSpeedMph":
            return String(format: "%.1f mph", entry.value)
        case "peakAccelG":
            return String(format: "%.2f G", entry.value)
        default:
            return String(format: "%.1f", entry.value)
        }
    }
}

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.orange : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
