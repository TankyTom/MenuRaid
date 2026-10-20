import SwiftUI

/// Array state, overall capacity and parity-check progress.
struct ArrayCard: View {
    @Environment(ServerStore.self) private var store

    var body: some View {
        let array = store.snapshot?.array
        Card("Array", trailing: {
            if let array {
                Chip(text: array.state?.capitalized ?? "Unknown", color: array.isStarted ? Palette.ok : Palette.bad)
            }
        }) {
            if let message = store.sectionErrors[.array] {
                SectionErrorBanner(section: .array, message: message)
            }
            if let array {
                capacity(array.capacity)
                parity(array.parityCheck)
            } else if store.sectionErrors[.array] == nil {
                LoadingRow()
            }
        }
    }

    @ViewBuilder
    private func capacity(_ capacity: ArrayCapacity?) -> some View {
        if let capacity, let fraction = capacity.usedFraction {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.bytes(kb: capacity.usedKB))
                        .font(.system(size: 28, weight: .bold))
                    Text("used of \(Format.bytes(kb: capacity.totalKB))")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.fraction(fraction)).font(.callout.weight(.medium)).monospacedDigit()
                }
                UsageBar(fraction: fraction, color: Palette.fill(fraction), height: 8)
                Text("\(Format.bytes(kb: capacity.freeKB)) free")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func parity(_ check: ParityCheck?) -> some View {
        if let check, check.running {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(check.paused ? "Parity check paused" : "Parity check running", systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout)
                    Spacer()
                    Text(Format.percent(check.progress)).font(.callout.weight(.medium)).monospacedDigit()
                }
                UsageBar(fraction: (check.progress ?? 0) / 100, color: Palette.warn, height: 6)
            }
        } else if let status = check?.status {
            Label("Last parity check: \(status.lowercased())", systemImage: "checkmark.shield")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// One row per parity, data and cache disk: status, name, usage, temperature and spin state.
struct DisksCard: View {
    @Environment(ServerStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let disks = store.snapshot?.array?.disks ?? []
        Card("Disks", trailing: {
            if !disks.isEmpty { Text("\(disks.count) disks").font(.caption).foregroundStyle(.secondary) }
        }) {
            if disks.isEmpty {
                if store.sectionErrors[.array] == nil { LoadingRow() }
            } else {
                VStack(spacing: 10) {
                    ForEach(disks) { disk in
                        DiskRow(disk: disk, thresholds: settings.preferences.thresholds)
                    }
                }
            }
        }
    }
}

struct DiskRow: View {
    let disk: DiskInfo
    let thresholds: Thresholds

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
                .frame(width: 18)
                .accessibilityLabel(disk.statusDescription)

            VStack(alignment: .leading, spacing: 1) {
                Text(disk.name).font(.callout.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 92, alignment: .leading)

            usage

            VStack(alignment: .trailing, spacing: 1) {
                tempText
                if let errors = disk.numErrors, errors > 0 {
                    Text(verbatim: "\(errors) errors")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.bad)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(width: 72, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var usage: some View {
        if let fraction = disk.usedFraction, disk.role != .parity {
            VStack(alignment: .leading, spacing: 2) {
                UsageBar(fraction: fraction, color: Palette.fill(fraction), height: 5)
                Text("\(Format.fraction(fraction)) of \(Format.bytes(kb: disk.fsSizeKB))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        } else {
            Text(disk.role == .parity ? Format.bytes(kb: disk.sizeKB) : "—")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Spun-down disks report no temperature; show a dash and a sleep icon, never 0.
    @ViewBuilder
    private var tempText: some View {
        if let temp = disk.tempC {
            Text("\(Int(temp.rounded()))°C")
                .font(.callout.weight(.medium)).monospacedDigit()
                .foregroundStyle(tempColor(temp))
        } else {
            HStack(spacing: 3) {
                if disk.isSpinning == false { Image(systemName: "moon.zzz.fill").font(.caption2) }
                Text("—").font(.callout)
            }
            .foregroundStyle(.secondary)
            .help(disk.isSpinning == false ? "Spun down" : "Temperature unavailable")
        }
    }

    private var subtitle: String {
        let role = disk.role == .data ? "Data" : disk.role.rawValue.capitalized
        return [role, disk.device].compactMap { $0 }.joined(separator: " · ")
    }

    private func tempColor(_ temp: Double) -> Color {
        if temp >= thresholds.critical(rotational: disk.rotational) { return Palette.bad }
        if temp >= thresholds.warn(rotational: disk.rotational) { return Palette.warn }
        return .primary
    }

    private var isHot: Bool {
        guard let temp = disk.tempC else { return false }
        return temp >= thresholds.warn(rotational: disk.rotational)
    }

    /// Different shapes as well as colours, so state isn't conveyed by colour alone.
    private var statusSymbol: String {
        if disk.isEmptySlot { return "minus.circle" }
        if disk.isFailed || (disk.numErrors ?? 0) > 0 { return "xmark.octagon.fill" }
        return isHot ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if disk.isEmptySlot { return Palette.idle }
        if disk.isFailed || (disk.numErrors ?? 0) > 0 { return Palette.bad }
        if let temp = disk.tempC, temp >= thresholds.critical(rotational: disk.rotational) { return Palette.bad }
        return isHot ? Palette.warn : Palette.ok
    }
}

#if DEBUG
#Preview("Array + disks (live)") {
    VStack(spacing: 12) { ArrayCard(); DisksCard() }
        .padding().frame(width: 360)
        .environment(PreviewFixtures.store(PreviewFixtures.live))
        .environment(PreviewFixtures.settings)
}
#Preview("Parity check running") {
    ArrayCard().padding().frame(width: 360)
        .environment(PreviewFixtures.store(PreviewFixtures.parityRunning))
}
#Preview("Hot disk") {
    DisksCard().padding().frame(width: 360)
        .environment(PreviewFixtures.store(PreviewFixtures.hotDisk))
        .environment(PreviewFixtures.settings)
}
#Preview("Array stopped") {
    VStack(spacing: 12) { ArrayCard(); DisksCard() }
        .padding().frame(width: 360)
        .environment(PreviewFixtures.store(PreviewFixtures.arrayStopped))
        .environment(PreviewFixtures.settings)
}
#endif
