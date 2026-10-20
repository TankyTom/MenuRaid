import Testing
import Foundation
@testable import MenuRaid

struct RedirectPolicyTests {
    private func allows(_ from: String, _ to: String) -> Bool {
        RedirectPolicy.allows(from: URL(string: from), to: URL(string: to))
    }

    @Test func followsSameHostRedirects() {
        #expect(allows("http://192.168.1.10/graphql", "http://192.168.1.10/login"))
        #expect(allows("https://tower.local/graphql", "https://tower.local:8443/graphql"))
        #expect(allows("https://Tower.local/graphql", "https://tower.LOCAL/graphql"))   // host case doesn't matter
    }

    @Test func allowsUpgradingToHTTPSOnTheSameHost() {
        #expect(allows("http://192.168.1.10/graphql", "https://192.168.1.10/graphql"))
        #expect(allows("http://tower.local/graphql", "https://tower.local:443/graphql"))
    }

    @Test func neverDowngradesFromHTTPS() {
        #expect(!allows("https://tower.local/graphql", "http://tower.local/graphql"))
    }

    @Test func refusesAnyOtherHost() {
        #expect(!allows("http://192.168.1.10/graphql", "http://evil.example/graphql"))
        #expect(!allows("https://tower.local/graphql", "https://evil.example/graphql"))
        #expect(!allows("http://192.168.1.10/graphql", "http://192.168.1.11/graphql"))
        // A lookalike that merely starts or ends with the real host.
        #expect(!allows("https://tower.local/graphql", "https://tower.local.evil.example/graphql"))
        #expect(!allows("https://tower.local/graphql", "https://eviltower.local/graphql"))
    }

    @Test func refusesOtherSchemesAndMissingParts() {
        #expect(!allows("http://tower.local/graphql", "ftp://tower.local/graphql"))
        #expect(!allows("http://tower.local/graphql", "file:///etc/passwd"))
        #expect(!RedirectPolicy.allows(from: nil, to: URL(string: "http://tower.local")))
        #expect(!RedirectPolicy.allows(from: URL(string: "http://tower.local"), to: nil))
    }

    @Test func aRefusedRedirectIsExplainedInPlainLanguage() {
        let problem = ConnectionProblem.classify(.http(302))
        guard case .unexpectedResponse(let detail) = problem else {
            Issue.record("expected an unexpected-response problem, got \(problem)")
            return
        }
        #expect(detail.contains("different address"))
        #expect(problem.explanation.contains("https://"))
        // Other statuses keep their own message.
        #expect(ConnectionProblem.classify(.http(502)) == .unexpectedResponse("The server answered with HTTP 502."))
    }
}
