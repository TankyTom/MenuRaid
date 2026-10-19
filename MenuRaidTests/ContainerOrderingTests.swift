import Testing
import Foundation
@testable import MenuRaid

struct ContainerOrderingTests {
    private func c(_ name: String, running: Bool = true) -> DockerContainer {
        DockerContainer(id: name, name: name, image: nil, state: running ? .running : .exited, statusText: nil, ports: [])
    }

    private func names(_ containers: [DockerContainer]) -> [String] { containers.map(\.name) }

    // MARK: Defaults

    @Test func defaultIsAlphabeticalIgnoringCase() {
        let list = [c("sonarr"), c("Bazarr"), c("audiobookshelf"), c("Radarr")]
        #expect(names(ContainerOrdering.display(list, custom: [], runningFirst: false)) == ["audiobookshelf", "Bazarr", "Radarr", "sonarr"])
    }

    @Test func defaultKeepsRunningContainersAboveStoppedOnes() {
        // This is exactly how the list behaved before custom ordering existed.
        let list = [c("zeta"), c("alpha", running: false), c("beta"), c("Aardvark", running: false)]
        #expect(names(ContainerOrdering.display(list, custom: [], runningFirst: true)) == ["beta", "zeta", "Aardvark", "alpha"])
    }

    // MARK: Custom order

    @Test func customOrderIsFollowed() {
        let list = [c("a"), c("b"), c("c"), c("d")]
        #expect(names(ContainerOrdering.display(list, custom: ["c", "a", "d", "b"], runningFirst: false)) == ["c", "a", "d", "b"])
    }

    @Test func runningFirstKeepsTheCustomOrderWithinEachGroup() {
        let list = [c("a"), c("b", running: false), c("c"), c("d", running: false)]
        let result = ContainerOrdering.display(list, custom: ["d", "c", "b", "a"], runningFirst: true)
        #expect(names(result) == ["c", "a", "d", "b"])
    }

    @Test func runningFirstOffFollowsTheOrderExactlyEvenForStoppedContainers() {
        let list = [c("a"), c("b", running: false), c("c")]
        #expect(names(ContainerOrdering.display(list, custom: ["b", "a", "c"], runningFirst: false)) == ["b", "a", "c"])
    }

    @Test func newContainersGoAfterTheCustomOnesAlphabetically() {
        let list = [c("zulu"), c("a"), c("b"), c("mike")]
        let result = ContainerOrdering.display(list, custom: ["b", "a"], runningFirst: false)
        #expect(names(result) == ["b", "a", "mike", "zulu"])
    }

    @Test func removedContainersInTheSavedOrderAreIgnored() {
        let list = [c("a"), c("c")]
        #expect(names(ContainerOrdering.display(list, custom: ["x", "c", "gone", "a"], runningFirst: false)) == ["c", "a"])
    }

    @Test func duplicateNamesInTheSavedOrderDontCrash() {
        let list = [c("a"), c("b")]
        #expect(names(ContainerOrdering.display(list, custom: ["b", "b", "a"], runningFirst: false)) == ["b", "a"])
    }

    @Test func emptyList() {
        #expect(ContainerOrdering.display([], custom: ["a"], runningFirst: true).isEmpty)
    }

    // MARK: Moving (same meaning as SwiftUI's move(fromOffsets:toOffset:))

    @Test func dragToTheEnd() {
        #expect(ContainerOrdering.moved(["a", "b", "c"], fromOffsets: IndexSet(integer: 0), toOffset: 3) == ["b", "c", "a"])
    }

    @Test func dragToTheTop() {
        #expect(ContainerOrdering.moved(["a", "b", "c"], fromOffsets: IndexSet(integer: 2), toOffset: 0) == ["c", "a", "b"])
    }

    @Test func dragDownOneSlotLandsAfterTheNextItem() {
        // Dropping "a" in the gap between "b" and "c" is destination 2.
        #expect(ContainerOrdering.moved(["a", "b", "c"], fromOffsets: IndexSet(integer: 0), toOffset: 2) == ["b", "a", "c"])
    }

    @Test func dragToItsOwnPlaceChangesNothing() {
        #expect(ContainerOrdering.moved(["a", "b", "c"], fromOffsets: IndexSet(integer: 1), toOffset: 1) == ["a", "b", "c"])
        #expect(ContainerOrdering.moved(["a", "b", "c"], fromOffsets: IndexSet(integer: 1), toOffset: 2) == ["a", "b", "c"])
    }

    @Test func dragSeveralAtOnce() {
        #expect(ContainerOrdering.moved(["a", "b", "c", "d"], fromOffsets: IndexSet([0, 1]), toOffset: 4) == ["c", "d", "a", "b"])
    }

    @Test func invalidMovesAreIgnored() {
        #expect(ContainerOrdering.moved(["a", "b"], fromOffsets: IndexSet(integer: 5), toOffset: 0) == ["a", "b"])
        #expect(ContainerOrdering.moved([], fromOffsets: IndexSet(integer: 0), toOffset: 0) == [])
    }

    @Test func arrowButtons() {
        let list = ["a", "b", "c"]
        #expect(ContainerOrdering.nudged(list, index: 1, by: -1) == ["b", "a", "c"])
        #expect(ContainerOrdering.nudged(list, index: 1, by: 1) == ["a", "c", "b"])
        #expect(ContainerOrdering.nudged(list, index: 0, by: -1) == list)   // already at the top
        #expect(ContainerOrdering.nudged(list, index: 2, by: 1) == list)    // already at the bottom
    }

    @Test func savingKeepsThePlaceOfAbsentContainers() {
        let saved = ContainerOrdering.merged(edited: ["b", "a"], previous: ["a", "gone", "b"])
        #expect(saved == ["b", "a", "gone"])
    }
}

@MainActor
struct ContainerOrderSettingsTests {
    private func makeStore(order: [String] = [], runningFirst: Bool = true) -> ServerStore {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "menuraid.order.\(UUID().uuidString)")!)
        settings.primary.containerOrder = order
        settings.preferences.dockerRunningFirst = runningFirst
        let store = ServerStore(settings: settings, autostart: false)
        func make(_ name: String, running: Bool) -> DockerContainer {
            DockerContainer(id: name, name: name, image: nil, state: running ? .running : .exited, statusText: nil, ports: [])
        }
        store.loadPreview(ServerSnapshot(
            serverID: settings.primary.id,
            containers: [make("plex", running: true), make("sonarr", running: false), make("bazarr", running: true)],
            fetchedAt: .now
        ))
        return store
    }

    @Test func panelUsesTheSavedOrder() {
        #expect(makeStore(order: ["sonarr", "plex", "bazarr"], runningFirst: false).orderedContainers.map(\.name) == ["sonarr", "plex", "bazarr"])
    }

    @Test func emptyingTheOrderReturnsToAlphabetical() {
        // "Reset to alphabetical" sets the saved order to empty.
        #expect(makeStore(order: [], runningFirst: false).orderedContainers.map(\.name) == ["bazarr", "plex", "sonarr"])
    }

    @Test func defaultsMatchTheOldBehaviour() {
        #expect(makeStore().orderedContainers.map(\.name) == ["bazarr", "plex", "sonarr"])
        #expect(AppPreferences().dockerRunningFirst)
    }

    @Test func orderAndOptionSurviveRelaunchAndOldSettingsStillLoad() throws {
        var config = ServerConfig(lanAddress: "x")
        config.containerOrder = ["b", "a"]
        #expect(try JSONDecoder().decode(ServerConfig.self, from: JSONEncoder().encode(config)).containerOrder == ["b", "a"])
        #expect(try JSONDecoder().decode(ServerConfig.self, from: Data(#"{"lanAddress":"x"}"#.utf8)).containerOrder.isEmpty)
        #expect(try JSONDecoder().decode(AppPreferences.self, from: Data(#"{"refreshInterval":60}"#.utf8)).dockerRunningFirst)
    }
}
