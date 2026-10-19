#if DEBUG
import SwiftUI

/// Debug-only tool: runs the GraphQL queries against your server and shows or saves the raw responses,
/// so the models can be fitted to what the server really returns.
struct TestQueryView: View {
    @Environment(SettingsStore.self) private var settings

    private let keychain = KeychainStore()
    private let pins = CertPinStore.shared
    @State private var client = UnraidClient()

    @State private var useRemote = false
    @State private var selected = Queries.presets[0]
    @State private var customQuery = ""
    @State private var output = ""
    @State private var isRunning = false
    @State private var pendingFingerprint: String?
    @State private var savedPath: String?

    private var addressText: String {
        useRemote ? settings.primary.remoteAddress : settings.primary.lanAddress
    }

    private var base: URL? { AddressParser.parse(addressText)?.baseURL }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Route", selection: $useRemote) {
                    Text("LAN").tag(false)
                    Text("Remote").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                Text(base?.absoluteString ?? "No valid address")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Query", selection: $selected) {
                ForEach(Queries.presets) { Text($0.name).tag($0) }
            }
            TextEditor(text: $customQuery)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 60)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
                .help("Optional custom query. If not empty it runs instead of the preset.")

            HStack {
                Button("Run") { Task { await run() } }
                    .disabled(isRunning || base == nil)
                Button("Run all & save") { Task { await runAllAndSave() } }
                    .disabled(isRunning || base == nil)
                if isRunning { ProgressView().controlSize(.small) }
            }

            if let fingerprint = pendingFingerprint, let host = base?.host {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unknown certificate for \(host)").bold()
                    Text("SHA-256: \(fingerprint)").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Button("Trust this certificate") {
                        pins.setPin(fingerprint, for: host)
                        pendingFingerprint = nil
                    }
                }
                .padding(8)
                .background(.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
            }

            if let savedPath {
                Text("Saved to \(savedPath)").font(.caption).textSelection(.enabled)
            }

            ScrollView {
                Text(output.isEmpty ? "Output appears here." : output)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(6)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding()
    }

    private func apiKey() -> String? {
        (try? keychain.get(account: settings.primary.id.uuidString)) ?? nil
    }

    /// Runs one query and returns pretty-printed JSON, or an error description.
    private func execute(_ query: String) async -> String {
        guard let base else { return "No valid address." }
        guard let key = apiKey() else { return "No API key saved. Add it in the Connection tab." }
        let start = ContinuousClock.now
        do {
            let data = try await client.rawQuery(query, base: base, apiKey: key, timeout: 30)
            pendingFingerprint = nil
            return Self.pretty(data)
        } catch let UnraidError.untrustedCertificate(fingerprint) {
            pendingFingerprint = fingerprint
            return "Certificate not trusted yet. Confirm the fingerprint below to pin it."
        } catch {
            return "Error after \(Self.seconds(start.duration(to: .now))): \(error.localizedDescription)"
        }
    }

    private static func seconds(_ d: Duration) -> String {
        let c = d.components
        return String(format: "%.1fs", Double(c.seconds) + Double(c.attoseconds) / 1e18)
    }

    private func run() async {
        isRunning = true
        defer { isRunning = false }
        let query = customQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = ContinuousClock.now
        let result = await execute(query.isEmpty ? selected.query : query)
        output = "// took \(Self.seconds(start.duration(to: .now)))\n" + result
    }

    private func runAllAndSave() async {
        isRunning = true
        defer { isRunning = false }
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return }
        let dir = support.appending(path: "MenuRaid/debug", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var summary = ""
        for preset in Queries.presets {
            let start = ContinuousClock.now
            let result = await execute(preset.query)
            let took = Self.seconds(start.duration(to: .now))
            try? result.write(to: dir.appending(path: "\(preset.name).json"), atomically: true, encoding: .utf8)
            summary += "\(preset.name): \(result.hasPrefix("Error") ? result : "ok") (\(took))\n"
        }
        savedPath = dir.path
        output = summary
    }

    private static func pretty(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else { return String(decoding: data, as: UTF8.self) }
        return String(decoding: formatted, as: UTF8.self)
    }
}
#endif
