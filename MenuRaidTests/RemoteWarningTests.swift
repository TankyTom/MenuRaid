import Testing
import Foundation
@testable import MenuRaid

struct HostScopeTests {
    private func scope(_ host: String) -> SecurityNotice.HostScope { SecurityNotice.scope(ofHost: host) }

    @Test func privateIPv4RangesAreNotThePublicInternet() {
        for host in ["10.0.0.1", "10.255.255.255", "172.16.0.1", "172.31.255.255", "192.168.1.50", "127.0.0.1", "169.254.1.1"] {
            #expect(scope(host) == .privateOrVPN, "\(host)")
        }
    }

    @Test func rangeBoundariesAreExact() {
        #expect(scope("172.15.255.255") == .publicInternet)   // just below 172.16.0.0/12
        #expect(scope("172.32.0.1") == .publicInternet)       // just above it
        #expect(scope("192.167.1.1") == .publicInternet)
        #expect(scope("192.169.1.1") == .publicInternet)
        #expect(scope("11.0.0.1") == .publicInternet)
        #expect(scope("9.255.255.255") == .publicInternet)
    }

    @Test func tailscaleRangeIsTreatedAsAVPN() {
        #expect(scope("100.64.0.1") == .privateOrVPN)
        #expect(scope("100.101.102.103") == .privateOrVPN)
        #expect(scope("100.127.255.255") == .privateOrVPN)
        #expect(scope("100.63.255.255") == .publicInternet)   // just below 100.64.0.0/10
        #expect(scope("100.128.0.1") == .publicInternet)      // just above it
    }

    @Test func publicIPv4() {
        for host in ["8.8.8.8", "1.1.1.1", "203.0.113.7", "93.184.216.34"] {
            #expect(scope(host) == .publicInternet, "\(host)")
        }
    }

    @Test func notAnIPv4AddressIsTreatedAsAName() {
        // 5 parts, or a part out of range, isn't an address: it falls through to name rules, which say "public".
        #expect(scope("1.2.3.4.5") == .publicInternet)
        #expect(scope("256.1.1.1") == .publicInternet)
        #expect(scope("10.0.0") == .publicInternet)
    }

    @Test func ipv6() {
        #expect(scope("::1") == .privateOrVPN)
        #expect(scope("fe80::1") == .privateOrVPN)
        #expect(scope("febf::1") == .privateOrVPN)
        #expect(scope("fd7a:115c:a1e0::1") == .privateOrVPN)   // Tailscale
        #expect(scope("fc00::1") == .privateOrVPN)
        #expect(scope("fe80::1%en0") == .privateOrVPN)
        #expect(scope("[fd7a::1]") == .privateOrVPN)
        #expect(scope("2001:4860:4860::8888") == .publicInternet)
        #expect(scope("fec0::1") == .publicInternet)           // just above link-local
    }

    @Test func localNamesAndVPNNames() {
        for host in ["tower", "nas", "tower.local", "TOWER.LOCAL", "tower.lan", "tower.home.arpa", "tower.internal",
                     "tower.tailnet-1234.ts.net", "tower.localdomain"] {
            #expect(scope(host) == .privateOrVPN, "\(host)")
        }
    }

    @Test func publicNames() {
        for host in ["example.com", "tower.example.com", "myserver.duckdns.org", "tower.local.example.com", "notts.net"] {
            #expect(scope(host) == .publicInternet, "\(host)")
        }
    }

    @Test func emptyIsNotTrusted() {
        #expect(scope("") == .publicInternet)
    }
}

struct RemoteHTTPWarningTests {
    private func config(remote: String, mode: RouteMode = .auto) -> ServerConfig {
        ServerConfig(lanAddress: "192.168.1.10", remoteAddress: remote, mode: mode)
    }

    @Test func plainHTTPToAPublicAddressWarns() {
        for remote in ["203.0.113.7", "http://example.com", "myserver.duckdns.org:8080"] {
            #expect(SecurityNotice.remoteUsesUnprotectedHTTP(config(remote: remote)), "\(remote)")
            #expect(SecurityNotice.shouldShowRemoteHTTPWarning(config: config(remote: remote), dismissed: false))
        }
    }

    @Test func tailscaleAndPrivateAddressesDoNotWarn() {
        // The setup this app was built around: a Tailscale IP or MagicDNS name over plain http.
        for remote in ["100.101.102.103", "tower.tailnet-1234.ts.net", "192.168.50.2", "tower.local", "tower", "[fd7a:115c:a1e0::1]"] {
            #expect(!SecurityNotice.remoteUsesUnprotectedHTTP(config(remote: remote)), "\(remote)")
        }
    }

    @Test func httpsNeverWarns() {
        #expect(!SecurityNotice.remoteUsesUnprotectedHTTP(config(remote: "https://example.com")))
        #expect(!SecurityNotice.remoteUsesUnprotectedHTTP(config(remote: "https://203.0.113.7")))
    }

    @Test func noRemoteAddressNoWarning() {
        #expect(!SecurityNotice.remoteUsesUnprotectedHTTP(config(remote: "")))
        #expect(!SecurityNotice.remoteUsesUnprotectedHTTP(config(remote: "not a url !!")))
    }

    @Test func lanOnlyModeNeverUsesTheRemoteSoItIsQuiet() {
        #expect(!SecurityNotice.shouldShowRemoteHTTPWarning(config: config(remote: "example.com", mode: .lan), dismissed: false))
        #expect(SecurityNotice.shouldShowRemoteHTTPWarning(config: config(remote: "example.com", mode: .remote), dismissed: false))
    }

    @Test func dismissedStaysDismissed() {
        #expect(!SecurityNotice.shouldShowRemoteHTTPWarning(config: config(remote: "example.com"), dismissed: true))
    }

    @Test func theLANWarningIsUnaffected() {
        // LAN rules still work exactly as before.
        let c = ServerConfig(lanAddress: "192.168.1.10", remoteAddress: "example.com")
        #expect(SecurityNotice.shouldShowHTTPWarning(config: c, dismissed: false))
        #expect(!SecurityNotice.shouldShowHTTPWarning(config: c, dismissed: true))
    }
}

@MainActor
struct RemoteWarningStoreTests {
    @Test func showsOnceThenStaysDismissedAcrossRelaunch() {
        let suite = "menuraid.remote.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        settings.primary.remoteAddress = "example.com"
        let store = ServerStore(settings: settings, autostart: false)
        #expect(store.showRemoteHTTPWarning)

        store.dismissRemoteHTTPWarning()
        #expect(!store.showRemoteHTTPWarning)

        let relaunched = ServerStore(settings: SettingsStore(defaults: defaults), autostart: false)
        #expect(!relaunched.showRemoteHTTPWarning)
    }

    @Test func dismissingTheLANNoticeDoesNotHideTheRemoteOne() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "menuraid.remote.\(UUID().uuidString)")!)
        settings.primary.lanAddress = "192.168.1.10"
        settings.primary.remoteAddress = "example.com"
        let store = ServerStore(settings: settings, autostart: false)
        store.dismissHTTPWarning()
        #expect(!store.showHTTPWarning)
        #expect(store.showRemoteHTTPWarning)
    }

    @Test func oldSettingsDefaultToNotDismissed() throws {
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: Data(#"{"httpWarningDismissed":true}"#.utf8))
        #expect(prefs.httpWarningDismissed)
        #expect(!prefs.remoteHTTPWarningDismissed)
    }
}
