import SwiftUI
import WidgetKit

/// Screen for connecting (or updating) a single provider by pasting an API key.
/// The key is validated with a live request and stored in the shared keychain.
struct ConnectProviderView: View {
    let provider: ProviderID
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var isConnected: Bool {
        KeychainStore.read(account: provider.keychainAccount) != nil
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    RingView(provider: provider,
                             snapshot: UsageStore.snapshots()[provider],
                             size: 56)
                    VStack(alignment: .leading) {
                        Text(provider.displayName).font(.title2.bold())
                        Text(isConnected ? "Connected" : "Not connected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("API key") {
                SecureField("Paste your \(provider.displayName) API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Link("Where do I get a key?", destination: provider.keyURL)
                    .font(.footnote)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
            if let successMessage {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.footnote)
            }

            Section {
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        if isValidating { ProgressView().padding(.trailing, 4) }
                        Text(isConnected ? "Update key" : "Connect")
                    }
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || isValidating)

                if isConnected {
                    Button("Remove", role: .destructive) {
                        KeychainStore.delete(account: provider.keychainAccount)
                        UsageStore.markDisconnected(provider)
                        WidgetCenter.shared.reloadAllTimelines()
                        onChanged()
                        dismiss()
                    }
                }
            }

            Section {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var footnote: String {
        switch provider {
        case .openai, .anthropic:
            return "Usage is read from the API's rate-limit headers each refresh. Validating sends one tiny request that costs at most a token or two."
        case .google:
            return "Google's API doesn't report a usage window, so the ring only shows that the key is connected."
        }
    }

    private func connect() async {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        isValidating = true
        errorMessage = nil
        successMessage = nil
        do {
            let snapshot = try await UsageProviderFactory.provider(for: provider).fetchUsage(apiKey: key)
            KeychainStore.save(key, account: provider.keychainAccount)
            UsageStore.markConnected(provider)
            UsageStore.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
            onChanged()
            successMessage = "Connected!"
            apiKey = ""
            isValidating = false
            try? await Task.sleep(nanoseconds: 500_000_000)
            dismiss()
        } catch {
            // OpenAI/Anthropic may authenticate fine but return no rate-limit
            // data on a brand-new key; treat that as a successful connection.
            if let usageError = error as? UsageError, case .noRateLimitData = usageError {
                KeychainStore.save(key, account: provider.keychainAccount)
                UsageStore.markConnected(provider)
                WidgetCenter.shared.reloadAllTimelines()
                onChanged()
                isValidating = false
                dismiss()
                return
            }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isValidating = false
        }
    }
}
