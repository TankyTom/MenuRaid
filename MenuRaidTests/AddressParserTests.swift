import Testing
import Foundation
@testable import MenuRaid

struct AddressParserTests {
    @Test func bareIPv4DefaultsToHTTP() {
        let parsed = AddressParser.parse("192.168.1.10")
        #expect(parsed == ParsedAddress(scheme: "http", host: "192.168.1.10", port: nil))
        #expect(parsed?.baseURL?.absoluteString == "http://192.168.1.10")
    }

    @Test func hostnameWithPort() {
        let parsed = AddressParser.parse("tower.local:8080")
        #expect(parsed == ParsedAddress(scheme: "http", host: "tower.local", port: 8080))
        #expect(parsed?.baseURL?.absoluteString == "http://tower.local:8080")
    }

    @Test func explicitHTTPSIsKept() {
        let parsed = AddressParser.parse("https://Tower.Tailnet-1234.ts.net")
        #expect(parsed?.scheme == "https")
        #expect(parsed?.host == "tower.tailnet-1234.ts.net")
        #expect(parsed?.isHTTPS == true)
    }

    @Test func tailscaleIP() {
        #expect(AddressParser.parse("100.101.102.103")?.host == "100.101.102.103")
    }

    @Test func whitespaceAndPathAreIgnored() {
        let parsed = AddressParser.parse("  http://192.168.1.10:80/Dashboard  ")
        #expect(parsed == ParsedAddress(scheme: "http", host: "192.168.1.10", port: 80))
    }

    @Test func ipv6IsBracketedInBaseURL() {
        let parsed = AddressParser.parse("http://[fd7a::1]:8080")
        #expect(parsed?.host == "fd7a::1")
        #expect(parsed?.baseURL?.absoluteString == "http://[fd7a::1]:8080")
    }

    @Test func rejectsEmptyUnsupportedSchemeAndBadPort() {
        #expect(AddressParser.parse("") == nil)
        #expect(AddressParser.parse("   ") == nil)
        #expect(AddressParser.parse("ftp://192.168.1.10") == nil)
        #expect(AddressParser.parse("192.168.1.10:99999") == nil)
        #expect(AddressParser.parse("http://") == nil)
    }
}
