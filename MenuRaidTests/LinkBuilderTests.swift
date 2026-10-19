import Testing
import Foundation
@testable import MenuRaid

struct LinkBuilderTests {
    private let lan = URL(string: "http://192.168.1.10")!

    private func container(_ name: String = "plex", ports: [PortMapping], webUI: String? = nil) -> DockerContainer {
        DockerContainer(id: name, name: name, image: nil, state: .running, statusText: nil, ports: ports, webUITemplate: webUI)
    }

    private func tcp(_ publicPort: Int?, private privatePort: Int = 80) -> PortMapping {
        PortMapping(ip: publicPort == nil ? "" : "0.0.0.0", privatePort: privatePort, publicPort: publicPort, type: "TCP")
    }

    // MARK: Pages

    @Test func webGUIPages() {
        #expect(LinkBuilder.page(.dashboard, base: lan).absoluteString == "http://192.168.1.10/Dashboard")
        #expect(LinkBuilder.page(.docker, base: lan).absoluteString == "http://192.168.1.10/Docker")
        #expect(LinkBuilder.page(.vms, base: lan).absoluteString == "http://192.168.1.10/VMs")
    }

    @Test func logAndStatusPages() {
        #expect(LinkBuilder.page(.main, base: lan).absoluteString == "http://192.168.1.10/Main")
        #expect(LinkBuilder.page(.systemLog, base: lan).absoluteString == "http://192.168.1.10/Tools/Syslog")
        #expect(LinkBuilder.page(.notifications, base: lan).absoluteString == "http://192.168.1.10/Tools/NotificationsArchive")
    }

    @Test func terminalAndFileManagerPages() {
        #expect(LinkBuilder.page(.terminal, base: lan).absoluteString == "http://192.168.1.10/webterminal/ttyd/")
        // The "?" and "/" in the query must not be percent-escaped.
        #expect(LinkBuilder.page(.fileManager, base: lan).absoluteString == "http://192.168.1.10/Main/Browse?dir=/mnt")
    }

    @Test func pagesWorkOnOtherPortsSchemesAndHostsAndIgnoreATrailingSlash() {
        let custom = URL(string: "https://tower.tailnet-1234.ts.net:8443/")!
        #expect(LinkBuilder.page(.fileManager, base: custom).absoluteString == "https://tower.tailnet-1234.ts.net:8443/Main/Browse?dir=/mnt")
        #expect(LinkBuilder.page(.dashboard, base: custom).absoluteString == "https://tower.tailnet-1234.ts.net:8443/Dashboard")
        let v6 = AddressParser.parse("http://[fd7a::1]:8080")!.baseURL!
        #expect(LinkBuilder.page(.terminal, base: v6).absoluteString == "http://[fd7a::1]:8080/webterminal/ttyd/")
    }

    @Test func pageButtonTitles() {
        #expect(LinkBuilder.Page.terminal.title == "Terminal")
        #expect(LinkBuilder.Page.fileManager.title == "File manager")
        #expect(LinkBuilder.Page.systemLog.title == "System log")
        #expect(LinkBuilder.Page.notifications.title == "Notifications")
        #expect(LinkBuilder.Page.main.title == "Main tab")
    }

    @Test func pagesKeepTheWebGUIPortAndScheme() {
        let base = URL(string: "https://tower.local:8443")!
        #expect(LinkBuilder.page(.vms, base: base).absoluteString == "https://tower.local:8443/VMs")
    }

    // MARK: Ports

    @Test func fallsBackToAPublishedTCPPortOnTheActiveHost() {
        let link = LinkBuilder.container(container(ports: [tcp(32400)]), base: lan, overrides: [:])
        #expect(link == .published(URL(string: "http://192.168.1.10:32400")!))
    }

    @Test func skipsUnpublishedAndUDPPorts() {
        let ports = [
            tcp(nil, private: 80),
            PortMapping(ip: "0.0.0.0", privatePort: 5353, publicPort: 5353, type: "UDP"),
            tcp(9000, private: 9000),
        ]
        #expect(LinkBuilder.container(container(ports: ports), base: lan, overrides: [:]).url?.port == 9000)
    }

    @Test func fallbackUsesTheLowestPublishedTCPPortNotTheListOrder() {
        // The API lists ports in no useful order (a real container listed its daemon port first).
        let ports = [tcp(58846, private: 58846), tcp(8112, private: 8112), tcp(9118, private: 9118)]
        let link = LinkBuilder.container(container("deluge", ports: ports), base: lan, overrides: [:])
        #expect(link.url?.port == 8112)
    }

    // MARK: WebUI template (what Unraid's own WebUI button uses)

    @Test func webUITemplateBeatsPortGuessing() {
        // Real binhex-delugevpn: the template says 8112 even though other ports are published.
        let ports = [tcp(58846, private: 58846), tcp(8112, private: 8112), tcp(8118, private: 8118)]
        let c = container("binhex-delugevpn", ports: ports, webUI: "http://[IP]:[PORT:8112]")
        #expect(LinkBuilder.container(c, base: lan, overrides: [:]) == .webUI(URL(string: "http://192.168.1.10:8112")!))
    }

    @Test func templatePortIsMappedToThePublicPort() {
        // Real audiobookshelf: container port 80 is published as 13378.
        let c = container("audiobookshelf", ports: [tcp(13378, private: 80)], webUI: "http://[IP]:[PORT:80]")
        #expect(LinkBuilder.container(c, base: lan, overrides: [:]).url?.absoluteString == "http://192.168.1.10:13378")
    }

    @Test func templateKeepsSchemeAndPath() {
        let https = container("master", ports: [tcp(7282, private: 8080)], webUI: "https://[IP]:[PORT:8080]")
        #expect(LinkBuilder.container(https, base: lan, overrides: [:]).url?.absoluteString == "https://192.168.1.10:7282")
        let path = container("bazarr", ports: [tcp(6767, private: 6767)], webUI: "http://[IP]:[PORT:6767]/system/status")
        #expect(LinkBuilder.container(path, base: lan, overrides: [:]).url?.absoluteString == "http://192.168.1.10:6767/system/status")
    }

    @Test func templateFollowsTheActiveRoute() {
        let c = container("deluge", ports: [tcp(8112, private: 8112)], webUI: "http://[IP]:[PORT:8112]")
        let remote = URL(string: "http://tower.tailnet-1234.ts.net")!
        #expect(LinkBuilder.container(c, base: remote, overrides: [:]).url?.absoluteString == "http://tower.tailnet-1234.ts.net:8112")
        let v6 = AddressParser.parse("http://[fd7a::1]")!.baseURL
        #expect(LinkBuilder.container(c, base: v6, overrides: [:]).url?.absoluteString == "http://[fd7a::1]:8112")
    }

    @Test func hostNetworkContainerUsesItsOwnPort() {
        // Real Jellyfin: no port mappings (host network), template says 8096.
        let c = container("Jellyfin", ports: [], webUI: "http://[IP]:[PORT:8096]")
        #expect(LinkBuilder.container(c, base: lan, overrides: [:]).url?.absoluteString == "http://192.168.1.10:8096")
    }

    @Test func templateWithAnUnpublishedPortFallsBack() {
        // Bridge container whose WebUI port isn't published: the template can't be used.
        let c = container("app", ports: [tcp(9000, private: 9000)], webUI: "http://[IP]:[PORT:8080]")
        #expect(LinkBuilder.container(c, base: lan, overrides: [:]) == .published(URL(string: "http://192.168.1.10:9000")!))
    }

    @Test func templateWithoutIPPlaceholderIsUsedAsWritten() {
        let c = container("app", ports: [], webUI: "https://app.example.com/")
        #expect(LinkBuilder.container(c, base: lan, overrides: [:]).url?.absoluteString == "https://app.example.com/")
        #expect(LinkBuilder.container(c, base: nil, overrides: [:]).url?.absoluteString == "https://app.example.com/")
    }

    @Test func templateNeedingAnAddressWithoutOneIsUnavailable() {
        let c = container("app", ports: [], webUI: "http://[IP]:[PORT:80]")
        #expect(LinkBuilder.container(c, base: nil, overrides: [:]) == .unavailable(.noServer))
    }

    @Test func badTemplatesAreIgnored() {
        for bad in ["", "   ", "ftp://[IP]:[PORT:21]", "http://[HOST]:[PORT:80]", "not a url"] {
            let c = container("app", ports: [tcp(9000, private: 9000)], webUI: bad)
            #expect(LinkBuilder.container(c, base: lan, overrides: [:]) == .published(URL(string: "http://192.168.1.10:9000")!), "\(bad)")
        }
    }

    @Test func overrideStillBeatsTheTemplate() {
        let c = container("deluge", ports: [tcp(8112, private: 8112)], webUI: "http://[IP]:[PORT:8112]")
        let link = LinkBuilder.container(c, base: lan, overrides: ["deluge": "https://deluge.example.com"])
        #expect(link == .override(URL(string: "https://deluge.example.com")!))
    }

    @Test func noPublishedPortIsUnavailableWithAHelpfulMessage() {
        for ports in [[], [tcp(nil)]] {
            let link = LinkBuilder.container(container(ports: ports), base: lan, overrides: [:])
            #expect(link == .unavailable(.noPublishedPort))
            #expect(link.url == nil)
            #expect(link.unavailableMessage == "No web UI or published port. Set a URL override in Settings.")
        }
    }

    @Test func noServerAddressIsUnavailable() {
        let link = LinkBuilder.container(container(ports: [tcp(80)]), base: nil, overrides: [:])
        #expect(link == .unavailable(.noServer))
    }

    // MARK: Host types and routes

    @Test func webGUIPortIsDroppedFromContainerLinks() {
        let base = URL(string: "http://192.168.1.10:8080")!
        #expect(LinkBuilder.container(container(ports: [tcp(3000)]), base: base, overrides: [:]).url?.absoluteString == "http://192.168.1.10:3000")
    }

    @Test func hostnamesAndMagicDNS() {
        let base = URL(string: "http://tower.tailnet-1234.ts.net")!
        #expect(LinkBuilder.container(container(ports: [tcp(8096)]), base: base, overrides: [:]).url?.absoluteString == "http://tower.tailnet-1234.ts.net:8096")
    }

    @Test func ipv6HostsAreBracketed() {
        let base = AddressParser.parse("http://[fd7a::1]:8080")!.baseURL
        #expect(LinkBuilder.container(container(ports: [tcp(8096)]), base: base, overrides: [:]).url?.absoluteString == "http://[fd7a::1]:8096")
    }

    @Test func lanAndRemoteRoutesGiveDifferentHostsForTheSameContainer() {
        let remote = URL(string: "http://100.101.102.103")!
        let plex = container(ports: [tcp(32400)])
        #expect(LinkBuilder.container(plex, base: lan, overrides: [:]).url?.host == "192.168.1.10")
        #expect(LinkBuilder.container(plex, base: remote, overrides: [:]).url?.host == "100.101.102.103")
    }

    @Test func containerLinksUseHTTPEvenWhenTheWebGUIUsesHTTPS() {
        let base = URL(string: "https://tower.local")!
        #expect(LinkBuilder.container(container(ports: [tcp(8096)]), base: base, overrides: [:]).url?.scheme == "http")
    }

    // MARK: Overrides

    @Test func overrideIsUsedExactly() {
        let overrides = ["plex": "https://plex.example.com/web/index.html?x=1#home"]
        let link = LinkBuilder.container(container(ports: [tcp(32400)]), base: lan, overrides: overrides)
        #expect(link == .override(URL(string: "https://plex.example.com/web/index.html?x=1#home")!))
    }

    @Test func overrideBeatsPortsAndWorksWithoutAnyPorts() {
        let overrides = ["plex": "https://plex.example.com"]
        #expect(LinkBuilder.container(container(ports: []), base: lan, overrides: overrides).url?.host == "plex.example.com")
        #expect(LinkBuilder.container(container(ports: [tcp(32400)]), base: lan, overrides: overrides).url?.host == "plex.example.com")
    }

    @Test func overrideWorksEvenWithNoServerAddress() {
        let link = LinkBuilder.container(container(ports: []), base: nil, overrides: ["plex": "https://plex.example.com"])
        #expect(link.url?.host == "plex.example.com")
    }

    @Test func overrideNamesMatchCaseInsensitively() {
        let link = LinkBuilder.container(container("Plex", ports: []), base: lan, overrides: ["plex": "https://plex.example.com"])
        #expect(link.url?.host == "plex.example.com")
    }

    @Test func overrideWithoutSchemeGetsHTTP() {
        #expect(LinkBuilder.parseOverride("nas.local:8112")?.absoluteString == "http://nas.local:8112")
        #expect(LinkBuilder.parseOverride("  https://a.example.com/x  ")?.absoluteString == "https://a.example.com/x")
    }

    @Test func emptyOrInvalidOverrideFallsBackToPorts() {
        for bad in ["", "   ", "ftp://x.example.com", "http://", "://", "not a url with spaces"] {
            let link = LinkBuilder.container(container(ports: [tcp(32400)]), base: lan, overrides: ["plex": bad])
            #expect(link == .published(URL(string: "http://192.168.1.10:32400")!), "override \"\(bad)\"")
        }
    }

    @Test func otherContainersAreUnaffectedByAnOverride() {
        let link = LinkBuilder.container(container("sonarr", ports: [tcp(8989)]), base: lan, overrides: ["plex": "https://plex.example.com"])
        #expect(link.url?.absoluteString == "http://192.168.1.10:8989")
    }

    // MARK: Settings storage

    @Test func overridesSurviveEncodingAndOldConfigsStillLoad() throws {
        var config = ServerConfig(lanAddress: "192.168.1.10")
        config.containerOverrides = ["plex": "https://plex.example.com"]
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)

        let old = #"{"id":"00000000-0000-0000-0000-000000000009","lanAddress":"192.168.1.10","remoteAddress":"","mode":"auto"}"#
        let loaded = try JSONDecoder().decode(ServerConfig.self, from: Data(old.utf8))
        #expect(loaded.lanAddress == "192.168.1.10")
        #expect(loaded.containerOverrides.isEmpty)
    }
}

struct VMConsoleLinkTests {
    private let lan = URL(string: "http://192.168.1.10")!

    private func vm(_ name: String = "Ubuntu", _ state: VMState = .running) -> VirtualMachine {
        VirtualMachine(id: name, name: name, state: state)
    }

    @Test func matchesUnraidsOwnConsoleLink() {
        // Copied from the "VNC Remote" link on a real server, minus the `v=` cache-buster.
        let url = LinkBuilder.vmConsole(vm(), base: lan, ports: ["Ubuntu": 5700])
        #expect(url?.absoluteString == "http://192.168.1.10/plugins/dynamix.vm.manager/vnc.html?resize=scale&autoconnect=true&host=192.168.1.10&port=&path=/wsproxy/5700/")
    }

    @Test func onlyRunningVMsWithAPortGetAConsole() {
        let ports = ["Ubuntu": 5700]
        for state in [VMState.shutoff, .paused, .idle, .crashed, .other] {
            #expect(LinkBuilder.vmConsole(vm("Ubuntu", state), base: lan, ports: ports) == nil, "\(state)")
        }
        #expect(LinkBuilder.vmConsole(vm(), base: lan, ports: [:]) == nil)
        #expect(LinkBuilder.vmConsole(vm(), base: nil, ports: ports) == nil)
    }

    @Test func invalidPortsAreIgnored() {
        for bad in [0, -1, 65536, 70000] {
            #expect(LinkBuilder.vmConsole(vm(), base: lan, ports: ["Ubuntu": bad]) == nil, "\(bad)")
        }
    }

    @Test func eachVMGetsItsOwnPortAndNamesMatchCaseInsensitively() {
        let ports = ["Ubuntu": 5700, "Windows 11 VM": 5701]
        #expect(LinkBuilder.vmConsole(vm("ubuntu"), base: lan, ports: ports)?.absoluteString.hasSuffix("/wsproxy/5700/") == true)
        #expect(LinkBuilder.vmConsole(vm("Windows 11 VM"), base: lan, ports: ports)?.absoluteString.hasSuffix("/wsproxy/5701/") == true)
    }

    @Test func followsTheActiveRouteAndWebGUIPort() {
        let remote = LinkBuilder.vmConsole(vm(), base: URL(string: "http://100.101.102.103")!, ports: ["Ubuntu": 5700])
        #expect(remote?.host == "100.101.102.103")
        #expect(remote?.absoluteString.contains("host=100.101.102.103&port=&") == true)

        let custom = LinkBuilder.vmConsole(vm(), base: URL(string: "https://tower.local:8443")!, ports: ["Ubuntu": 5700])
        #expect(custom?.absoluteString == "https://tower.local:8443/plugins/dynamix.vm.manager/vnc.html?resize=scale&autoconnect=true&host=tower.local&port=8443&path=/wsproxy/5700/")
    }

    @Test func ipv6HostsAreEncodedInsteadOfCrashing() {
        let base = AddressParser.parse("http://[fd7a::1]")!.baseURL
        let url = LinkBuilder.vmConsole(vm(), base: base, ports: ["Ubuntu": 5700])
        #expect(url?.absoluteString == "http://[fd7a::1]/plugins/dynamix.vm.manager/vnc.html?resize=scale&autoconnect=true&host=%5Bfd7a::1%5D&port=&path=/wsproxy/5700/")
    }

    @Test func portsSurviveEncodingAndOldConfigsStillLoad() throws {
        var config = ServerConfig(lanAddress: "192.168.1.10")
        config.vmConsolePorts = ["Ubuntu": 5700]
        #expect(try JSONDecoder().decode(ServerConfig.self, from: JSONEncoder().encode(config)) == config)
        let old = try JSONDecoder().decode(ServerConfig.self, from: Data(#"{"lanAddress":"x"}"#.utf8))
        #expect(old.vmConsolePorts.isEmpty)
    }
}
