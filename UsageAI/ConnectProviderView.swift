import SwiftUI
import WidgetKit

/// Screen for connecting (or updating) a single provider. Shows an OAuth
/// sign-in section (when the provider has an OAuth config) and/or an API-key
/// section. OAuth is what surfaces the plan's 5-hour + weekly windows; a key
/// yields the API rate-limit window instead.
struct ConnectProviderView: View {
    let provider: ProviderID
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var authenticator = WebAuthenticator()

    @State private var apiKey = ""
    @State private var pastedCode = ""
    @State private var pendingManual: WebAuthenticator.ManualAuthorization?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var isConnected: Bool { CredentialStore.isConnected(provider) }
    private var oauthConfig: OAuthConfig? { OAuthConfig.config(for: provider) }

    var body: some View {
        Form {
            header

            if oauthConfig != nil { oauthSection }
            if provider.supportsAPIKey { apiKeySection }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.footnote)
            }
            if let successMessage {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.footnote)
            }
            if isConnected {
                Section {
                    Button("Disconnect", role: .destructive, action: disconnect)
                }
            }
            Section { Text(footnote).font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    private var header: some View {
        Section {
            HStack {
                RingView(provider: provider,
                         snapshot: UsageStore.snapshots()[provider],
                         size: 56)
                VStack(alignment: .leading) {
                    Text(provider.displayName).font(.title2.bold())
                    Text(isConnected ? "Connected · \(provider.windowLabel)" : "Not connected")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var oauthSection: some View {
        if let config = oauthConfig, config.isConfigured {
            if config.usesManualCodeEntry {
                manualOAuthSection(config: config)
            } else {
                Section {
                    Button {
                        Task { await signInWithScheme(config: config) }
                    } label: {
                        workingLabel(isConnected ? "Re-authorize \(provider.displayName)"
                                                 : "Sign in with \(provider.displayName)")
                    }
                    .disabled(isWorking)
                }
            }
        } else {
            Section("Setup required") {
                Text("Add an OAuth client ID for \(provider.displayName) in `OAuthConfig.swift` to enable sign-in. See the README.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func manualOAuthSection(config: OAuthConfig) -> some View {
        Section("Sign in") {
            Button {
                let manual = authenticator.manualAuthorization(config: config)
                pendingManual = manual
                errorMessage = nil
                openURL(manual.url)
            } label: {
                workingLabel("Open \(provider.displayName) sign-in")
            }
            Text("Authorize in the browser, then copy the code it shows and paste it below.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        Section("Authorization code") {
            TextField("Paste code here", text: $pastedCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button {
                Task { await completeManual(config: config) }
            } label: {
                workingLabel("Connect")
            }
            .disabled(pastedCode.trimmingCharacters(in: .whitespaces).isEmpty
                      || pendingManual == nil || isWorking)
        }
    }

    private var apiKeySection: some View {
        Section(oauthConfig != nil ? "Or use an API key" : "API key") {
            SecureField("Paste your \(provider.displayName) API key", text: $apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Link("Where do I get a key?", destination: provider.keyURL)
                .font(.footnote)
            Button {
                Task { await connectAPIKey() }
            } label: {
                workingLabel(isConnected ? "Update key" : "Connect")
            }
            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
        }
    }

    @ViewBuilder
    private func workingLabel(_ title: String) -> some View {
        HStack {
            if isWorking { ProgressView().padding(.trailing, 4) }
            Text(title)
        }
    }

    // MARK: Actions

    private func signInWithScheme(config: OAuthConfig) async {
        begin()
        do {
            let token = try await authenticator.login(config: config)
            try await finish(credential: .oauth(token))
        } catch {
            fail(error)
        }
    }

    private func completeManual(config: OAuthConfig) async {
        guard let manual = pendingManual else { return }
        begin()
        do {
            let token = try await authenticator.exchange(config: config, manual: manual, code: pastedCode)
            try await finish(credential: .oauth(token))
        } catch {
            fail(error)
        }
    }

    private func connectAPIKey() async {
        begin()
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        do {
            try await finish(credential: .apiKey(key))
        } catch UsageError.noRateLimitData {
            // Authenticated but no window yet — still a valid connection.
            persist(.apiKey(key), snapshot: nil)
            done()
        } catch {
            fail(error)
        }
    }

    /// Validates a credential with a live usage request, persists it on success,
    /// and dismisses.
    private func finish(credential: Credential) async throws {
        let snapshot = try await UsageProviderFactory.provider(for: provider).fetchUsage(credential: credential)
        persist(credential, snapshot: snapshot)
        done()
    }

    private func persist(_ credential: Credential, snapshot: UsageSnapshot?) {
        CredentialStore.save(credential, for: provider)
        UsageStore.markConnected(provider)
        if let snapshot { UsageStore.save(snapshot) }
        WidgetCenter.shared.reloadAllTimelines()
        onChanged()
    }

    private func disconnect() {
        CredentialStore.delete(provider)
        UsageStore.markDisconnected(provider)
        WidgetCenter.shared.reloadAllTimelines()
        onChanged()
        dismiss()
    }

    private func begin() { isWorking = true; errorMessage = nil; successMessage = nil }

    private func done() {
        isWorking = false
        successMessage = "Connected!"
        apiKey = ""; pastedCode = ""; pendingManual = nil
        Task { try? await Task.sleep(nanoseconds: 500_000_000); dismiss() }
    }

    private func fail(_ error: Error) {
        isWorking = false
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private var footnote: String {
        switch provider {
        case .anthropic:
            return "Sign in with your Claude account. Usage reflects the 5-hour session window read from the API response headers. This uses Anthropic's login flow and may change."
        case .google:
            return "Sign in with Google (OAuth). Google doesn't expose a subscription usage window, so the ring shows connection status only."
        case .openai:
            return "OpenAI has no OAuth for API access, so paste an API key. Usage reflects the API rate-limit window. Validating sends one tiny request."
        }
    }
}
