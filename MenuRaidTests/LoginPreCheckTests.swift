import Testing
import Foundation
@testable import MenuRaid

struct LoginPageTests {
    @Test func readsTheServerNameFromTheRealLoginPage() {
        // The title Unraid serves, as captured from a real server.
        let html = #"<head><meta charset="utf-8"><title>Tower/Login</title><style>"#
        #expect(LoginPage.serverName(in: html) == "Tower")
    }

    @Test func toleratesCaseAndWhitespace() {
        #expect(LoginPage.serverName(in: "<TITLE> Tower / login </TITLE>") == "Tower")
        #expect(LoginPage.serverName(in: "<title>my-server.local/Login</title>") == "my-server.local")
        #expect(LoginPage.serverName(in: "<title>nas_01/Login</title>") == "nas_01")
    }

    @Test func anythingElseIsUnreadable() {
        let bad = [
            "", "no title here",
            "<title>Login</title>",                       // no name
            "<title>/Login</title>",                      // empty name
            "<title>Tower/Dashboard</title>",             // not the login page
            "<title>a/b/Login</title>",                   // ambiguous
            "<title>My NAS/Login</title>",                // not a hostname
            "<title><script>x</script>/Login</title>",    // markup in the name
            "<title>Tower\u{0435}/Login</title>",         // lookalike non-ASCII letter
        ]
        for html in bad {
            #expect(LoginPage.serverName(in: html) == nil, "\(html)")
        }
    }

    @Test func ignoresATitleBeyondTheReadLimit() {
        let padding = String(repeating: "x", count: LoginPage.maxBytes + 10)
        #expect(LoginPage.serverName(in: padding + "<title>Tower/Login</title>") == nil)
    }
}

/// The key must not be sent to a plain-HTTP LAN address until its login page names our server.
struct LoginPreCheckResolverTests {
    private func config(
        lan: String = "192.168.1.10", remote: String = "100.101.102.103",
        mode: RouteMode = .auto, expected: String? = "Tower"
    ) -> ServerConfig {
        ServerConfig(lanAddress: lan, remoteAddress: remote, mode: mode, expectedHostname: expected)
    }

    @Test func aMatchingNameThenAllowsTheKeyedProbe() async {
        let prober = MockProber(["192.168.1.10": .server(hostname: "Tower")], loginNames: ["192.168.1.10": .name("TOWER")])
        let result = await RouteResolver.resolve(config(), apiKey: "k", prober: prober)
        #expect(result.route?.kind == .lan)
        #expect(prober.loginCalls.count == 1)
        #expect(prober.calls.count == 1)
    }

    @Test func aDifferentNameNeverReceivesTheKey() async {
        let prober = MockProber(
            ["192.168.1.10": .server(hostname: "Tower")],      // would match, if it were ever asked
            loginNames: ["192.168.1.10": .name("Someone-Elses-NAS")]
        )
        let result = await RouteResolver.resolve(config(), apiKey: "k", prober: prober)
        #expect(result.route?.kind == .remote)
        #expect(result.note?.contains("Someone-Elses-NAS") == true)
        #expect(prober.calls.isEmpty)                           // the key was never sent
    }

    @Test func aDifferentNameExplainsHowToFixARename() async {
        let prober = MockProber(["192.168.1.10": .server(hostname: "NewName")], loginNames: ["192.168.1.10": .name("NewName")])
        let result = await RouteResolver.resolve(config(), apiKey: "k", prober: prober)
        let note = result.note ?? ""
        #expect(note.contains("\"NewName\", not \"Tower\""))
        #expect(note.contains("Reset"))
        #expect(note.contains("Server identity"))
        #expect(note.contains("Settings → Connection"))
    }

    @Test func noHintBeforeAnyNameHasBeenSaved() async {
        // With nothing saved there is nothing to reset, and nothing can mismatch.
        let prober = MockProber(["192.168.1.10": .server(hostname: "Tower")])
        let result = await RouteResolver.resolve(config(expected: nil), apiKey: "k", prober: prober)
        #expect(result.note == nil)
    }

    @Test func anUnreadableNameFailsSafe() async {
        let prober = MockProber(["192.168.1.10": .server(hostname: "Tower")], loginNames: ["192.168.1.10": .unreadable])
        let result = await RouteResolver.resolve(config(), apiKey: "k", prober: prober)
        #expect(result.route?.kind == .remote)
        #expect(result.note?.contains("didn't send your API key") == true)
        #expect(prober.calls.isEmpty)
    }

    @Test func anUnreadableNameWithNoRemoteMeansNoRoute() async {
        let prober = MockProber(["192.168.1.10": .server(hostname: "Tower")], loginNames: ["192.168.1.10": .unreadable])
        let result = await RouteResolver.resolve(config(remote: ""), apiKey: "k", prober: prober)
        #expect(result.route == nil)
        #expect(prober.calls.isEmpty)
    }

    @Test func noAnswerFallsBackLikeBefore() async {
        let prober = MockProber(loginNames: ["192.168.1.10": .failed(.unreachable("timed out"))])
        let withRemote = await RouteResolver.resolve(config(), apiKey: "k", prober: prober)
        #expect(withRemote.route?.kind == .remote)
        let lanOnly = await RouteResolver.resolve(config(remote: ""), apiKey: "k", prober: prober)
        #expect(lanOnly.route?.kind == .lan)                    // unchanged: a slow LAN-only server keeps being tried
        #expect(prober.calls.isEmpty)
    }

    @Test func thePreCheckUsesTheOneSecondTimeout() async {
        let prober = MockProber(["192.168.1.10": .server(hostname: "Tower")])
        _ = await RouteResolver.resolve(config(), apiKey: "k", prober: prober)
        #expect(prober.loginCalls.first?.timeout == 1.0)
    }

    @Test func httpsAddressesSkipItBecauseThePinnedCertificateAlreadyProtectsThem() async {
        let prober = MockProber(["tower.local": .server(hostname: "Tower")])
        let result = await RouteResolver.resolve(config(lan: "https://tower.local"), apiKey: "k", prober: prober)
        #expect(result.route?.kind == .lan)
        #expect(prober.loginCalls.isEmpty)
    }

    @Test func theFirstConnectionHasNothingToCompareWithSoItSkipsIt() async {
        let prober = MockProber(["192.168.1.10": .server(hostname: "Tower")])
        let none = await RouteResolver.resolve(config(expected: nil), apiKey: "k", prober: prober)
        let empty = await RouteResolver.resolve(config(expected: ""), apiKey: "k", prober: prober)
        #expect(none.route?.kind == .lan)
        #expect(empty.route?.kind == .lan)
        #expect(prober.loginCalls.isEmpty)
    }

    @Test func fixedModesDoNotCheck() async {
        let prober = MockProber()
        _ = await RouteResolver.resolve(config(mode: .lan), apiKey: "k", prober: prober)
        _ = await RouteResolver.resolve(config(mode: .remote), apiKey: "k", prober: prober)
        #expect(prober.loginCalls.isEmpty)
    }
}
