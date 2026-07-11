import SwiftUI
import WidgetKit

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var snapshots: [ProviderID: UsageSnapshot] = [:]
    @Published var connected: [ProviderID] = []
    @Published var isRefreshing = false

    func load() {
        connected = UsageStore.connectedProviders()
        snapshots = UsageStore.snapshots()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let results = await UsageRefresher.refreshAll()
        snapshots = Dictionary(uniqueKeysWithValues: results.map { ($0.provider, $0) })
        connected = UsageStore.connectedProviders()
        isRefreshing = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    func disconnect(_ id: ProviderID) {
        KeychainStore.delete(account: id.keychainAccount)
        UsageStore.markDisconnected(id)
        load()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct ContentView: View {
    @StateObject private var model = UsageViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer(minLength: 0)
                        UsageRingsView(providers: model.connected,
                                       snapshots: model.snapshots,
                                       ringSize: 64)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Session usage")
                }

                Section("Services") {
                    ForEach(ProviderID.allCases) { provider in
                        ProviderRow(provider: provider,
                                    isConnected: model.connected.contains(provider),
                                    snapshot: model.snapshots[provider],
                                    onChanged: { model.load() },
                                    onDisconnect: { model.disconnect(provider) })
                    }
                }

                Section {
                    Text("Rings show each provider's API rate-limit window: how much of the current token budget you've used and when it resets. Add the **Usage AI** widget to your Home Screen to see them at a glance. Google doesn't report a usage window, so its ring is shown as indeterminate.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Usage AI")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        if model.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(model.isRefreshing || model.connected.isEmpty)
                }
            }
            .refreshable { await model.refresh() }
            .onAppear {
                model.load()
                if !model.connected.isEmpty { Task { await model.refresh() } }
            }
        }
    }
}

struct ProviderRow: View {
    let provider: ProviderID
    let isConnected: Bool
    let snapshot: UsageSnapshot?
    let onChanged: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        if isConnected {
            NavigationLink {
                ConnectProviderView(provider: provider, onChanged: onChanged)
            } label: {
                HStack(spacing: 12) {
                    RingView(provider: provider, snapshot: snapshot, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.displayName).font(.headline)
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
            .swipeActions {
                Button(role: .destructive, action: onDisconnect) {
                    Label("Remove", systemImage: "trash")
                }
            }
        } else {
            NavigationLink {
                ConnectProviderView(provider: provider, onChanged: onChanged)
            } label: {
                HStack(spacing: 12) {
                    RingView(provider: provider, snapshot: nil, size: 40)
                    Text(provider.displayName).font(.headline)
                    Spacer()
                    Text("Connect").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var detail: String {
        guard let snapshot else { return "Connected" }
        if let error = snapshot.errorMessage { return error }
        if !snapshot.hasWindow { return "Connected · usage window not reported" }
        return "\(snapshot.percentUsed)% used · \(Formatting.resetString(snapshot.resetsAt))"
    }
}

#Preview {
    ContentView()
}
