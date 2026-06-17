import SwiftUI

struct DogListView: View {
    @StateObject private var vm = DogListViewModel()
    @State private var showingAddDog = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.dogs.isEmpty {
                    ProgressView("Loading...")
                } else if vm.dogs.isEmpty {
                    ContentUnavailableView("No Dogs Yet", systemImage: "pawprint",
                                          description: Text("Add your first dog to get started."))
                } else {
                    List(vm.dogs) { dog in
                        NavigationLink(destination: DogDetailView(dog: dog)) {
                            DogRowView(dog: dog)
                        }
                    }
                }
            }
            .navigationTitle("My Dogs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddDog = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddDog) {
                AddDogView { name, breed, weight in
                    await vm.addDog(name: name, breed: breed, weightLbs: weight)
                }
            }
            .task { await vm.loadDogs() }
        }
    }
}

struct DogRowView: View {
    let dog: Dog

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.orange.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay { Image(systemName: "pawprint.fill").foregroundStyle(.orange) }

            VStack(alignment: .leading, spacing: 2) {
                Text(dog.name).font(.headline)
                if let breed = dog.breed {
                    Text(breed).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
