import Foundation

/// How the Docker list is ordered. Pure, so the rules are easy to test.
///
/// - With no custom order saved, containers are alphabetical (ignoring case): the default, and what "Reset" returns to.
/// - A custom order is a list of container names. Containers in it keep that order; containers that aren't in it
///   (new ones) follow, alphabetically. Names in it that no longer exist are ignored but remembered.
/// - "Running first" (on by default) then lifts running containers above stopped ones, keeping the order within each group.
nonisolated enum ContainerOrdering {
    /// The order the user edits: custom order first, then any containers it doesn't mention, alphabetically.
    static func baseOrder(_ containers: [DockerContainer], custom: [String]) -> [DockerContainer] {
        let position = Dictionary(custom.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return containers.sorted { lhs, rhs in
            switch (position[lhs.name], position[rhs.name]) {
            case let (a?, b?): return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.name.lowercased() < rhs.name.lowercased()
            }
        }
    }

    /// The order shown in the panel.
    static func display(_ containers: [DockerContainer], custom: [String], runningFirst: Bool) -> [DockerContainer] {
        let base = baseOrder(containers, custom: custom)
        guard runningFirst else { return base }
        return base.filter { $0.state.isRunning } + base.filter { !$0.state.isRunning }
    }

    // MARK: Editing

    /// Moves items like SwiftUI's `move(fromOffsets:toOffset:)`, which is what a drag in a list reports.
    static func moved(_ names: [String], fromOffsets source: IndexSet, toOffset destination: Int) -> [String] {
        let valid = source.filter { names.indices.contains($0) }
        guard !valid.isEmpty else { return names }
        var result = names
        let moving = valid.map { names[$0] }
        let removedBefore = valid.filter { $0 < destination }.count
        for index in valid.sorted(by: >) { result.remove(at: index) }
        let target = min(max(destination - removedBefore, 0), result.count)
        result.insert(contentsOf: moving, at: target)
        return result
    }

    /// One step up (`-1`) or down (`+1`); no change at the ends.
    static func nudged(_ names: [String], index: Int, by step: Int) -> [String] {
        let target = index + step
        guard names.indices.contains(index), names.indices.contains(target) else { return names }
        // Moving down by one needs destination index + 2 in "move" terms (the slot after the next item).
        return moved(names, fromOffsets: IndexSet(integer: index), toOffset: step > 0 ? target + 1 : target)
    }

    /// Saves the order just edited without losing the place of containers that are temporarily absent
    /// (stopped and removed, or not loaded right now): they stay in the list after the visible ones.
    static func merged(edited visible: [String], previous: [String]) -> [String] {
        let keep = previous.filter { !visible.contains($0) }
        return visible + keep
    }
}
