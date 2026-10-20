import Testing
import Foundation
@testable import MenuRaid

/// Decodes real responses captured from an Unraid 7.2.3 server (MenuRaid/Fixtures/live).
struct DecodingTests {
    private struct Envelope<T: Decodable>: Decodable { let data: T }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(Envelope<T>.self, from: Data(json.utf8)).data
    }

    private func fixture<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let json = try #require(FixtureJSON.named(name), "missing fixture \(name)")
        return try JSONDecoder().decode(Envelope<T>.self, from: Data(json.utf8)).data
    }

    @Test func overviewDecodes() throws {
        let overview = try fixture(OverviewResponse.self, "overview").overview
        #expect(overview.hostname == "Tower")
        #expect(overview.unraidVersion == "7.2.3")
        #expect(overview.cpuThreads == 12)
        #expect(overview.bootTime != nil)
        #expect((overview.cpuPercent ?? 0) > 0)
    }

    @Test func uptimeIsComputedFromBootTimestamp() throws {
        let boot = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!
        var overview = ServerOverview()
        overview.bootTime = boot
        #expect(overview.uptime(now: boot.addingTimeInterval(3600)) == 3600)
        #expect(overview.uptime(now: boot.addingTimeInterval(-5)) == 0)
    }

    @Test func arrayMergesExtrasAndParity() throws {
        let info = ArrayInfo.make(
            array: try fixture(ArrayResponse.self, "array"),
            extras: try fixture(DiskExtrasResponse.self, "diskExtras"),
            parity: try fixture(ParityCheckResponse.self, "parityCheck")
        )
        #expect(info.isStarted)
        #expect(info.disks.count == 6)
        #expect(info.disks.map(\.role) == [.parity, .data, .data, .data, .cache, .cache])

        let disk1 = try #require(info.disks.first { $0.name == "disk1" })
        #expect(!disk1.isStatusOK)
        #expect(disk1.statusDescription == "Disabled")
        #expect(disk1.numErrors == 1023)
        #expect(disk1.isSpinning == false)
        #expect(disk1.tempC == nil)

        // Parity and cache disks get the extras too; `cache` is an SSD, `backup` is a spun-down HDD.
        #expect(info.disks.first { $0.name == "parity" }?.isSpinning == true)
        #expect(info.disks.first { $0.name == "cache" }?.rotational == false)
        #expect(info.disks.first { $0.name == "backup" }?.isSpinning == false)

        // Capacity arrives as strings; it must still decode.
        #expect(info.capacity?.totalKB == 23_998_278_513)
        #expect(info.parityCheck?.running == false)
        #expect(info.parityCheck?.status == "COMPLETED")
    }

    @Test func dockerStripsSlashAndKeepsPortlessContainers() throws {
        let containers = try fixture(DockerResponse.self, "docker").containers
        #expect(containers.count == 34)
        #expect(containers.allSatisfy { !$0.name.hasPrefix("/") })
        let imaginary = try #require(containers.first { $0.name == "nextcloud-aio-imaginary" })
        #expect(imaginary.ports.isEmpty)
        #expect(imaginary.state == .running)
        #expect(containers.first { $0.name == "nextcloud-aio-borgbackup" }?.state == .exited)
    }

    @Test func vmsAndNotificationsDecode() throws {
        let vms = try fixture(VMsResponse.self, "vms").vms
        #expect(vms.map(\.name) == ["Ubuntu", "Windows 11 VM"])
        #expect(vms.map(\.state) == [.running, .shutoff])

        let unread = try fixture(NotificationsResponse.self, "notifications").unread
        #expect(unread.alert == 19 && unread.warning == 10 && unread.total == 108)
    }

    // MARK: Leniency

    @Test func missingAndOddFieldsDontDropData() throws {
        let json = #"""
        {"data":{"docker":{"containers":[
          {"names":["/a"],"state":"RUNNING","ports":[{"publicPort":"8080","type":"TCP"},{"publicPort":null}]},
          {"state":"RUNNING"},
          {"names":["/b"]}
        ]}}}
        """#
        let containers = try decode(DockerResponse.self, json).containers
        #expect(containers.map(\.name) == ["a", "b"])          // nameless entry dropped, others kept
        #expect(containers[0].ports.first?.publicPort == 8080) // string port tolerated
        #expect(containers[1].state == .unknown)                // missing state
    }

    @Test func emptySectionsDecodeToEmptyLists() throws {
        #expect(try decode(DockerResponse.self, #"{"data":{"docker":{"containers":[]}}}"#).containers.isEmpty)
        #expect(try decode(VMsResponse.self, #"{"data":{"vms":{"domains":[]}}}"#).vms.isEmpty)
    }

    @Test func overviewToleratesMissingMetrics() throws {
        let overview = try decode(OverviewResponse.self, #"{"data":{"info":{"os":{"hostname":"x"}}}}"#).overview
        #expect(overview.hostname == "x")
        #expect(overview.cpuPercent == nil)
        #expect(overview.bootTime == nil)
    }

    @Test func uptimeAcceptsSecondsAsFallback() throws {
        let overview = try decode(OverviewResponse.self, #"{"data":{"info":{"os":{"uptime":3600}}}}"#).overview
        let uptime = try #require(overview.uptime())
        #expect(abs(uptime - 3600) < 5)
    }
}
