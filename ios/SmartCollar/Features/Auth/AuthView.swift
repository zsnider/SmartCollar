import SwiftUI

struct AuthView: View {
    @StateObject private var vm = AuthViewModel()
    @State private var isRegistering = false
    @State private var email = ""
    @State private var displayName = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "pawprint.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)

                Text("SmartCollar")
                    .font(.largeTitle.bold())

                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textFieldStyle(.roundedBorder)

                    if isRegistering {
                        TextField("Display Name", text: $displayName)
                            .textContentType(.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    SecureField("Password", text: $password)
                        .textContentType(isRegistering ? .newPassword : .password)
                        .textFieldStyle(.roundedBorder)
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button {
                    Task {
                        if isRegistering {
                            await vm.register(email: email, displayName: displayName, password: password)
                        } else {
                            await vm.login(email: email, password: password)
                        }
                    }
                } label: {
                    Group {
                        if vm.isLoading {
                            ProgressView()
                        } else {
                            Text(isRegistering ? "Create Account" : "Sign In")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(vm.isLoading)

                Button(isRegistering ? "Already have an account? Sign In" : "New here? Create Account") {
                    isRegistering.toggle()
                    vm.errorMessage = nil
                }
                .font(.caption)

                Spacer()
            }
            .padding(.horizontal, 32)
        }
    }
}
