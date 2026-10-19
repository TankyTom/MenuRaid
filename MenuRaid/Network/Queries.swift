import Foundation

/// GraphQL queries, one per panel section so each can fail independently.
/// These are unverified against a live server; the debug Test query tab is used to check and adjust them.
nonisolated enum Queries {
    struct Preset: Identifiable, Hashable, Sendable {
        let name: String
        let query: String
        var id: String { name }
    }

    static let identity = "{ info { os { hostname } } }"

    static let overview = """
    { info { os { hostname distro release uptime } cpu { brand cores threads }
             versions { core { unraid } } }
      metrics { cpu { percentTotal } memory { total used percentTotal } } }
    """

    static let array = """
    { array { state capacity { kilobytes { free used total } }
      parities { name device size temp status }
      disks { name device size temp status fsSize fsUsed fsFree }
      caches { name device size temp status fsSize fsUsed fsFree } } }
    """

    /// Spin state, error count and SSD-or-not for every disk (verified on 7.2.3).
    static let diskExtras = """
    { array { parities { name isSpinning numErrors rotational }
              disks { name isSpinning numErrors rotational }
              caches { name isSpinning numErrors rotational } } }
    """

    static let parityCheck = "{ array { parityCheckStatus { running paused progress errors status } } }"

    static let docker = """
    { docker { containers { id names state status image ports { ip privatePort publicPort type } labels } } }
    """

    static let vms = "{ vms { domains { id name state } } }"

    static let notifications = "{ notifications { overview { unread { info warning alert total } } } }"

    // Introspection helpers for fields whose real shape is uncertain.
    static let version = "{ info { versions { core { unraid } } } }"

    static let notificationsType = """
    { __type(name: "Notifications") { fields { name type { name kind ofType { name kind } } } } }
    """

    /// What fields does a VM have? Looking for a VNC/console port or URL.
    static let vmDomainType = """
    { vmDomain: __type(name: "VmDomain") { fields { name type { name kind ofType { name kind } } } }
      vms: __type(name: "Vms") { fields { name type { name kind ofType { name kind ofType { name } } } } } }
    """

    static let vmMutationsAndQueries = """
    { mutations: __type(name: "VmMutations") { fields { name } }
      query: __type(name: "Query") { fields { name } } }
    """

    /// What fields does a container have? Looking for labels or a WebUI URL.
    static let dockerContainerType = """
    { __type(name: "DockerContainer") { fields { name type { name kind ofType { name kind ofType { name } } } } } }
    """

    /// Probes for Unraid's per-container WebUI setting. Any of these may not exist on a given version.
    static let dockerLabels = "{ docker { containers { names labels } } }"
    static let dockerWebUI = "{ docker { containers { names webUiUrl } } }"
    static let dockerTemplatePorts = "{ docker { containers { names templatePorts { privatePort publicPort type } lanIpPorts } } }"

    static let queryRoot = "{ __schema { queryType { fields { name } } } }"

    /// Everything the debug tool can run, in the order shown in the picker.
    static let presets: [Preset] = [
        Preset(name: "identity", query: identity),
        Preset(name: "overview", query: overview),
        Preset(name: "array", query: array),
        Preset(name: "diskExtras", query: diskExtras),
        Preset(name: "parityCheck", query: parityCheck),
        Preset(name: "docker", query: docker),
        Preset(name: "vms", query: vms),
        Preset(name: "notifications", query: notifications),
        Preset(name: "version", query: version),
        Preset(name: "introspect-notifications", query: notificationsType),
        Preset(name: "introspect-vm", query: vmDomainType),
        Preset(name: "introspect-docker", query: dockerContainerType),
        Preset(name: "docker-labels", query: dockerLabels),
        Preset(name: "docker-webui", query: dockerWebUI),
        Preset(name: "docker-templatePorts", query: dockerTemplatePorts),
        Preset(name: "introspect-root-fields", query: vmMutationsAndQueries),
        Preset(name: "introspect-query-root", query: queryRoot),
    ]
}
