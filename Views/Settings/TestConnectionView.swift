import SwiftUI

/// "Test connection": checks the LAN and remote addresses separately and explains what it found.
struct TestConnectionSection: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ServerStore.self) private var store

    @State private var reports: [ConnectionReport] = []
    @State private var isRunning = false
    @State private var hasRun = false
    @State private var repinTarget: ConnectionReport?

    var body: some View {
        Section {
            HStack {
                Button("Test connection") { Task { await run() } }
                    .disabled(isRunning || !settings.primary.hasAnyAddress)
                if isRunning { ProgressView().controlSize(.small) }
            }

            if hasRun && reports.isEmpty && !isRunning {
                Text("Enter a LAN or remote address first.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(reports) { report in
                ReportView(report: report, onTrust: trust, onRepin: { repinTarget = $0 })
            }

            identityRow
        } header: {
            Text("Connection")
        } footer: {
            Text("In Auto mode MenuRaid uses the LAN address when your server answers there, otherwise the remote address.")
        }
        .confirmationDialog(
            "Trust the new certificate?",
            isPresented: Binding(get: { repinTarget != nil }, set: { if !$0 { repinTarget = nil } }),
            presenting: repinTarget
        ) { report in
            Button("Trust new certificate", role: .destructive) {
                if case .changed(_, let got)? = report.certificate, let host = report.url?.host {
                    store.trustCertificate(fingerprint: got, host: host)
                    Task { await run() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { report in
            if case .changed(let expected, let got)? = report.certificate {
                Text("Only continue if you changed the certificate on your server yourself.\n\nTrusted: \(expected)\nNow: \(got)")
            }
        }
    }

    /// Hostname saved at first connection; used to confirm the LAN address is really your server.
    @ViewBuilder
    private var identityRow: some View {
        HStack {
            if let name = settings.primary.expectedHostname {
                Label("Server identity: \(name)", systemImage: "checkmark.seal")
                    .font(.callout)
                Spacer()
                Button("Reset") { store.resetServerIdentity() }
                    .help("Forget this name. The next successful connection saves the name it finds.")
            } else {
                Label("Server identity: saved on first successful connection", systemImage: "seal")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func run() async {
        isRunning = true
        defer { isRunning = false; hasRun = true }
        reports = await store.testConnection()
    }

    private func trust(_ report: ConnectionReport) {
        guard case .untrusted(let fingerprint)? = report.certificate, let host = report.url?.host else { return }
        store.trustCertificate(fingerprint: fingerprint, host: host)
        Task { await run() }
    }
}

private struct ReportView: View {
    let report: ConnectionReport
    let onTrust: (ConnectionReport) -> Void
    let onRepin: (ConnectionReport) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: report.kind == .lan ? "house.fill" : "globe")
                Text(report.kind == .lan ? "LAN" : "Remote").font(.callout.weight(.semibold))
                Text(report.url?.absoluteString ?? report.address).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: report.isUsable ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(report.isUsable ? Palette.ok : Palette.bad)
                    .accessibilityLabel(report.isUsable ? "Working" : "Not working")
            }

            line("Reachable", report.reachable ? .yes : .no)
            line("API key accepted", report.apiKey)
            if let hostname = report.hostname {
                detail("Hostname", hostname, identityText)
            }
            if let certificate = report.certificate { certificateLine(certificate) }
            if let latency = report.latency { detail("Response time", "\(Int((latency * 1000).rounded())) ms", nil) }

            if let message = report.message {
                Text(message).font(.caption).foregroundStyle(report.isUsable ? Color.secondary : Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var identityText: String? {
        switch report.identity {
        case .matches: "matches the saved server"
        case .differs(let expected): "expected \(expected)"
        case .willBeSaved: "will be saved"
        case .unknown: nil
        }
    }

    private func line(_ title: String, _ check: ConnectionReport.Check) -> some View {
        HStack(spacing: 6) {
            Image(systemName: check == .yes ? "checkmark" : check == .no ? "xmark" : "questionmark")
                .foregroundStyle(check == .yes ? Palette.ok : check == .no ? Palette.bad : Color.secondary)
                .frame(width: 14)
            Text(title).font(.caption)
            Spacer()
            Text(check == .yes ? "Yes" : check == .no ? "No" : "Unknown").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func detail(_ title: String, _ value: String, _ note: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle").foregroundStyle(.secondary).frame(width: 14)
            Text(title).font(.caption)
            Spacer()
            Text([value, note.map { "(\($0))" }].compactMap { $0 }.joined(separator: " "))
                .font(.caption).foregroundStyle(report.isIdentityMismatch && title == "Hostname" ? Palette.bad : .secondary)
        }
    }

    @ViewBuilder
    private func certificateLine(_ certificate: ConnectionReport.Certificate) -> some View {
        switch certificate {
        case .notEncrypted:
            detail("Encryption", "None (HTTP)", "key and data are sent unencrypted")
        case .trustedBySystem:
            detail("Certificate", "Trusted by macOS", nil)
        case .pinned:
            detail("Certificate", "Pinned", "matches the one you trusted")
        case .untrusted(let fingerprint):
            VStack(alignment: .leading, spacing: 4) {
                detail("Certificate", "Not trusted yet", nil)
                Text("SHA-256 \(fingerprint)").font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
            }
        case .changed:
            detail("Certificate", "Changed", "blocked")
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch report.certificate {
        case .untrusted?:
            Button("Trust this certificate") { onTrust(report) }
        case .changed?:
            Button("Trust new certificate…", role: .destructive) { onRepin(report) }
        default:
            EmptyView()
        }
    }
}

#if DEBUG
#Preview("Reports") {
    let lan = ConnectionReport.make(
        kind: .lan, address: "192.168.1.10", url: URL(string: "http://192.168.1.10"),
        outcome: .success("Tower"), latency: 0.042, expectedHostname: "Tower", hasPin: false
    )
    let remote = ConnectionReport.make(
        kind: .remote, address: "100.64.0.1", url: URL(string: "http://100.64.0.1"),
        outcome: .failure(.unreachable("The request timed out.")), latency: nil, expectedHostname: "Tower", hasPin: false
    )
    return Form {
        ReportView(report: lan, onTrust: { _ in }, onRepin: { _ in })
        ReportView(report: remote, onTrust: { _ in }, onRepin: { _ in })
    }
    .formStyle(.grouped).frame(width: 520, height: 420)
}
#endif
