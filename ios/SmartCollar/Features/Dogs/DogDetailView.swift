import SwiftUI

struct DogDetailView: View {
    @StateObject private var vm: DogDetailViewModel
    @State private var showCollarPairing = false
    @State private var showStartSession = false

    init(dog: Dog) {
        _vm = StateObject(wrappedValue: DogDetailViewModel(dog: dog))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: Header
                profileHeader

                Divider()

                // MARK: Stats
                if let stats = vm.stats {
                    statsSection(stats)
                    Divider()
                }

                // MARK: Collars
                collarSection

                Divider()

                // MARK: Session History
                sessionHistorySection
            }
        }
        .navigationTitle(vm.dog.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showStartSession = true
                } label: {
                    Label("Start Session", systemImage: "play.circle.fill")
                }
                .disabled(vm.collars.isEmpty)
            }
        }
        .sheet(isPresented: $showCollarPairing) {
            CollarPairingView(dog: vm.dog) { newCollar in
                vm.collars.append(newCollar)
            }
        }
        .sheet(isPresented: $showStartSession) {
            if let collar = vm.collars.first {
                NavigationStack {
                    SessionView(dog: vm.dog, collar: collar, locationId: nil)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showStartSession = false }
                            }
                        }
                }
            }
        }
        .task { await vm.load() }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(.orange.opacity(0.15))
                .frame(width: 90, height: 90)
                .overlay {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                }

            VStack(spacing: 4) {
                Text(vm.dog.name)
                    .font(.title2.bold())
                if let breed = vm.dog.breed {
                    Text(breed)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let weight = vm.dog.weightLbs {
                    Text(String(format: "%.0f lbs", weight))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Stats

    private func statsSection(_ stats: DogStats) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "All-Time Stats")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    value: "\(stats.totalSessions)",
                    label: "Sessions",
                    icon: "flag.checkered",
                    color: .orange
                )
                StatCard(
                    value: formatSteps(stats.totalSteps),
                    label: "Total Steps",
                    icon: "figure.walk",
                    color: .blue
                )
                StatCard(
                    value: String(format: "%.1f mph", stats.bestSpeedMph),
                    label: "Top Speed",
                    icon: "speedometer",
                    color: .green
                )
                StatCard(
                    value: formatDuration(stats.totalDurationSecs),
                    label: "Time Active",
                    icon: "clock.fill",
                    color: .purple
                )
            }

            if let park = stats.favoritePark {
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Favorite Spot")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(park)
                            .font(.subheadline.bold())
                    }
                    Spacer()
                    Text("\(stats.favoriteParkVisits) visits")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }

    // MARK: - Collars

    private var collarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Collars")
                Spacer()
                Button {
                    showCollarPairing = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline)
                }
            }
            .padding(.horizontal)
            .padding(.top)

            if vm.collars.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No collar paired yet. Tap Add to connect one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom)
            } else {
                ForEach(vm.collars) { collar in
                    CollarRow(collar: collar) {
                        Task { await vm.removeCollar(collar) }
                    }
                }
                .padding(.bottom)
            }
        }
    }

    // MARK: - Session History

    private var sessionHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent Sessions")
                .padding(.horizontal)
                .padding(.top)

            if vm.isLoading && vm.sessions.isEmpty {
                ProgressView().padding()
            } else if vm.sessions.isEmpty {
                Text("No sessions recorded yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom)
            } else {
                ForEach(vm.sessions.prefix(10)) { session in
                    SessionRow(session: session)
                }
                .padding(.bottom)
            }
        }
    }

    // MARK: - Helpers

    private func formatSteps(_ steps: Int) -> String {
        steps >= 1000 ? String(format: "%.1fk", Double(steps) / 1000) : "\(steps)"
    }

    private func formatDuration(_ secs: Int) -> String {
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Sub-views

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct CollarRow: View {
    let collar: Collar
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(collar.provider.rawValue.capitalized)
                    .font(.subheadline.bold())
                if let uuid = collar.bleServiceUUID {
                    Text(uuid)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let extId = collar.externalId {
                    Text(extId)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let synced = collar.lastSyncedAt {
                Text(synced.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) { onRemove() } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.startedAt, style: .date)
                    .font(.subheadline.bold())
                Text(session.startedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 16) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(session.totalSteps)")
                        .font(.subheadline.bold())
                    Text("steps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f", session.maxSpeedMph))
                        .font(.subheadline.bold())
                    Text("mph")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let dur = session.durationSecs {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatDuration(dur))
                            .font(.subheadline.bold())
                        Text("time")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func formatDuration(_ secs: Int) -> String {
        let m = secs / 60
        let s = secs % 60
        return m > 0 ? "\(m)m\(s)s" : "\(s)s"
    }
}
