import Foundation

/// An Unraid version such as `7.2.3`, `7.3.0-rc.2` or `7.1.0-beta.1`, comparable so "is there a newer release?" is exact.
/// A pre-release (`-rc.1`) is older than the same version without one.
nonisolated struct UnraidVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    /// The part after `-`, split on dots (e.g. `["rc", "2"]`). Empty for a normal release.
    let prerelease: [String]

    /// Parses "7.2.3", "7.2", "v7.3.0-rc.2". Returns nil if it doesn't start with a number.
    init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") { trimmed.removeFirst() }
        let halves = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let core = halves.first else { return nil }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.count <= 3, !numbers.contains(nil), let major = numbers[0] else { return nil }
        self.major = major
        self.minor = numbers.count > 1 ? numbers[1] ?? 0 : 0
        self.patch = numbers.count > 2 ? numbers[2] ?? 0 : 0
        self.prerelease = halves.count > 1 ? halves[1].split(separator: ".").map(String.init) : []
    }

    var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
    }

    static func < (lhs: UnraidVersion, rhs: UnraidVersion) -> Bool {
        if (lhs.major, lhs.minor, lhs.patch) != (rhs.major, rhs.minor, rhs.patch) {
            return (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return false
        case (false, true): return true      // 7.3.0-rc.1 < 7.3.0
        case (true, false): return false
        case (false, false): return comparePrerelease(lhs.prerelease, rhs.prerelease) < 0
        }
    }

    /// Compares identifiers one by one: numbers numerically, everything else alphabetically, numbers before words.
    private static func comparePrerelease(_ a: [String], _ b: [String]) -> Int {
        for (x, y) in zip(a, b) {
            switch (Int(x), Int(y)) {
            case let (i?, j?): if i != j { return i < j ? -1 : 1 }
            case (_?, nil): return -1
            case (nil, _?): return 1
            case (nil, nil): if x != y { return x < y ? -1 : 1 }
            }
        }
        return a.count == b.count ? 0 : (a.count < b.count ? -1 : 1)
    }
}
