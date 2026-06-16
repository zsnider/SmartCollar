import SwiftUI

struct AddDogView: View {
    let onSave: (String, String?, Double?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var breed = ""
    @State private var weightText = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Dog Info") {
                    TextField("Name *", text: $name)
                    TextField("Breed (optional)", text: $breed)
                    TextField("Weight lbs (optional)", text: $weightText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Add Dog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !name.isEmpty else { return }
                        isSaving = true
                        Task {
                            await onSave(
                                name,
                                breed.isEmpty ? nil : breed,
                                Double(weightText)
                            )
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty || isSaving)
                }
            }
        }
    }
}
