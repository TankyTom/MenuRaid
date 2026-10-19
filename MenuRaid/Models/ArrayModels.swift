import Foundation

nonisolated enum DiskRole: String, Codable, Sendable {
    case parity, data, cache
}

/// One physical disk (parity, data or cache). Sizes are in KiB, as the Unraid API reports them.
nonisolated struct DiskInfo: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var role: DiskRole
    var device: String?
    var sizeKB: Double?
    /// Celsius. nil when the disk is spun down or the temperature is unavailable.
    var tempC: Double?
    /// Raw API status, e.g. `DISK_OK`, `DISK_DSBL`.
    var status: String?
    var fsSizeKB: Double?
    var fsUsedKB: Double?
    var fsFreeKB: Double?
    var isSpinning: Bool?
    var numErrors: Int?
    /// true = spinning disk, false = SSD/NVMe, nil = unknown (treated as HDD for thresholds).
    var rotational: Bool?

    var id: String { "\(role.rawValue)-\(name)" }

    var isStatusOK: Bool { status == "DISK_OK" }

    /// Fraction of the filesystem in use (0...1), if known.
    var usedFraction: Double? {
        guard let used = fsUsedKB, let size = fsSizeKB, size > 0 else { return nil }
        return min(1, max(0, used / size))
    }

    var statusDescription: String {
        switch status {
        case "DISK_OK": "OK"
        case "DISK_DSBL": "Disabled"
        case "DISK_NP", "DISK_NP_DSBL", "DISK_NP_MISSING": "Missing"
        case "DISK_INVALID": "Invalid"
        case "DISK_NEW": "New"
        case "DISK_WRONG": "Wrong disk"
        case .some(let other): other.replacingOccurrences(of: "DISK_", with: "").capitalized
        case .none: "Unknown"
        }
    }
}

nonisolated struct ParityCheck: Codable, Equatable, Sendable {
    var running: Bool
    var paused: Bool
    /// 0...100
    var progress: Double?
    var errors: Int?
    var status: String?
}

nonisolated struct ArrayCapacity: Codable, Equatable, Sendable {
    var freeKB: Double?
    var usedKB: Double?
    var totalKB: Double?

    var usedFraction: Double? {
        guard let used = usedKB, let total = totalKB, total > 0 else { return nil }
        return min(1, max(0, used / total))
    }
}

nonisolated struct ArrayInfo: Codable, Equatable, Sendable {
    /// Raw state, e.g. `STARTED`, `STOPPED`.
    var state: String?
    var capacity: ArrayCapacity?
    /// Parity disks first, then data disks, then cache pools.
    var disks: [DiskInfo]
    var parityCheck: ParityCheck?

    var isStarted: Bool { state == "STARTED" }
}

// MARK: - GraphQL response shapes

/// Raw disk fields from `Queries.array` (parities, disks and caches share this shape).
nonisolated struct RawDisk: Decodable, Sendable {
    var name: String?
    var device: String?
    var size: Double?
    var temp: Double?
    var status: String?
    var fsSize: Double?
    var fsUsed: Double?
    var fsFree: Double?

    private enum Keys: String, CodingKey { case name, device, size, temp, status, fsSize, fsUsed, fsFree }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        name = c.lenient(String.self, .name)
        device = c.lenient(String.self, .device)
        size = c.lenientDouble(.size)
        temp = c.lenientDouble(.temp)
        status = c.lenient(String.self, .status)
        fsSize = c.lenientDouble(.fsSize)
        fsUsed = c.lenientDouble(.fsUsed)
        fsFree = c.lenientDouble(.fsFree)
    }

    func disk(role: DiskRole) -> DiskInfo? {
        guard let name else { return nil }
        return DiskInfo(
            name: name, role: role, device: device, sizeKB: size, tempC: temp, status: status,
            fsSizeKB: fsSize, fsUsedKB: fsUsed, fsFreeKB: fsFree
        )
    }
}

nonisolated struct ArrayResponse: Decodable, Sendable {
    var state: String?
    var capacity: ArrayCapacity?
    var parities: [RawDisk]
    var disks: [RawDisk]
    var caches: [RawDisk]

    private enum Root: String, CodingKey { case array }
    private enum Keys: String, CodingKey { case state, capacity, parities, disks, caches }
    private enum Capacity: String, CodingKey { case kilobytes }
    private enum Kilobytes: String, CodingKey { case free, used, total }

    init(from decoder: Decoder) throws {
        let array = try decoder.container(keyedBy: Root.self).nestedContainer(keyedBy: Keys.self, forKey: .array)
        state = array.lenient(String.self, .state)
        parities = array.lenientArray(.parities)
        disks = array.lenientArray(.disks)
        caches = array.lenientArray(.caches)

        if let capacityBox = try? array.nestedContainer(keyedBy: Capacity.self, forKey: .capacity),
           let kb = try? capacityBox.nestedContainer(keyedBy: Kilobytes.self, forKey: .kilobytes) {
            capacity = ArrayCapacity(freeKB: kb.lenientDouble(.free), usedKB: kb.lenientDouble(.used), totalKB: kb.lenientDouble(.total))
        }
    }
}

/// Response of `Queries.diskExtras`.
nonisolated struct DiskExtrasResponse: Decodable, Sendable {
    struct Extra: Decodable, Sendable {
        var name: String?
        var isSpinning: Bool?
        var numErrors: Int?
        var rotational: Bool?

        private enum Keys: String, CodingKey { case name, isSpinning, numErrors, rotational }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            name = c.lenient(String.self, .name)
            isSpinning = c.lenient(Bool.self, .isSpinning)
            numErrors = c.lenientInt(.numErrors)
            rotational = c.lenient(Bool.self, .rotational)
        }
    }

    var disks: [Extra]

    private enum Root: String, CodingKey { case array }
    private enum Keys: String, CodingKey { case disks, parities, caches }

    /// Reads whichever of `disks`, `parities` and `caches` the query asked for.
    init(from decoder: Decoder) throws {
        let array = try decoder.container(keyedBy: Root.self).nestedContainer(keyedBy: Keys.self, forKey: .array)
        let parities: [Extra] = array.lenientArray(.parities)
        let data: [Extra] = array.lenientArray(.disks)
        let caches: [Extra] = array.lenientArray(.caches)
        disks = parities + data + caches
    }
}

/// Response of `Queries.parityCheck`.
nonisolated struct ParityCheckResponse: Decodable, Sendable {
    var parityCheck: ParityCheck?

    private enum Root: String, CodingKey { case array }
    private enum Keys: String, CodingKey { case parityCheckStatus }
    private enum Status: String, CodingKey { case running, paused, progress, errors, status }

    init(from decoder: Decoder) throws {
        let array = try decoder.container(keyedBy: Root.self).nestedContainer(keyedBy: Keys.self, forKey: .array)
        guard let c = try? array.nestedContainer(keyedBy: Status.self, forKey: .parityCheckStatus) else { return }
        parityCheck = ParityCheck(
            running: c.lenient(Bool.self, .running) ?? false,
            paused: c.lenient(Bool.self, .paused) ?? false,
            progress: c.lenientDouble(.progress),
            errors: c.lenientInt(.errors),
            status: c.lenient(String.self, .status)
        )
    }
}

extension ArrayInfo {
    /// Combines the three array queries. Extras and parity are optional so a failure in either
    /// still leaves a usable array section.
    nonisolated static func make(
        array: ArrayResponse,
        extras: DiskExtrasResponse?,
        parity: ParityCheckResponse?
    ) -> ArrayInfo {
        var disks = array.parities.compactMap { $0.disk(role: .parity) }
            + array.disks.compactMap { $0.disk(role: .data) }
            + array.caches.compactMap { $0.disk(role: .cache) }

        let extrasByName = Dictionary(
            (extras?.disks ?? []).compactMap { extra in extra.name.map { ($0, extra) } },
            uniquingKeysWith: { first, _ in first }
        )
        for index in disks.indices {
            if let extra = extrasByName[disks[index].name] {
                disks[index].isSpinning = extra.isSpinning
                disks[index].numErrors = extra.numErrors
                disks[index].rotational = extra.rotational
            }
        }
        return ArrayInfo(state: array.state, capacity: array.capacity, disks: disks, parityCheck: parity?.parityCheck)
    }
}
