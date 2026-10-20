# MenuRaid

A small macOS menu bar app that monitors an Unraid server. It shows a coloured status symbol in the menu bar and, when clicked, a panel with the server's health, array and disks, Docker containers and VMs.

*MenuRaid is an independent app for Unraid. It is not made by or affiliated with Lime Technology, Inc. "Unraid" is their trademark.*

Version 1 is **read-only**: it never starts, stops or changes anything on your server.

## What you get

- **Menu bar:** a status symbol (check, triangle or octagon, so it never relies on colour alone) plus one value you choose: CPU %, RAM %, hottest disk temperature, or icon only.
- **Status:** green, amber or red, with the reasons spelled out.
  - Red: array not started, a disk disabled/missing/invalid, any disk with errors, a disk at its critical temperature, or the server unreachable.
  - Amber: parity check running, a disk at its warning temperature, unread alert or warning notifications, or stale data.
- **System:** CPU and RAM with small history charts, uptime, Unraid version.
- **Array and disks:** capacity, parity-check progress, and one row per parity, data and cache disk with temperature, usage, error count and spun-down state.
- **Docker:** running containers first. Click one to open its web UI.
- **VMs:** click one to open its VNC console (if you've set its port) or Unraid's VMs page.
- **Update hint (optional):** a small "↑ 7.3.3" beside the Unraid version when a newer stable release exists, and a small "↑ N updates" in the Docker header for containers with a newer image.
- **Footer:** unread notification count, open the Unraid webGUI, light/dark switch, Settings, Quit.
- **At home or away:** it uses your LAN address when your server answers there and your remote address (for example Tailscale) otherwise, and switches by itself when your network changes.

## Requirements

- macOS 14.6 or later.
- Unraid **7.2 or later**, which has the GraphQL API built in.
- An Unraid **API key**. Create one in the Unraid webGUI under **Settings → Management Access → API Keys**, with the **Viewer** role. Version 1 only reads, so it needs nothing more.

## Setup

1. Launch MenuRaid. With nothing configured it opens **Settings** for you. (It has no Dock icon; look for it in the menu bar.)
2. **Connection:**
   - **LAN address:** your server's address at home, e.g. `192.168.1.10` or `tower.local`.
   - **Remote address (optional):** how you reach it away from home, e.g. a Tailscale IP `100.x.y.z` or `tower.tailnet-xxxx.ts.net`. This can be any reachable host; it isn't tied to Tailscale.
   - Both accept an IP or hostname, with an optional `https://` and an optional `:port`. With no scheme, `http://` is assumed.
   - **Mode:** *Auto* (recommended), *Always LAN* or *Always remote*.
3. Paste your **API key** and press **Save key**. It is stored in the macOS Keychain, never in a file or in settings.
4. Press **Test connection**. For each address it reports whether it's reachable, whether the key is accepted, the server's hostname, encryption and response time.

### How Auto mode chooses

It asks your LAN address "who are you?" with a 1 second timeout, and uses it only if the answering server has the same hostname that was saved at your first successful connection (and, for HTTPS, the same pinned certificate). Otherwise it uses the remote address. This keeps your API key from being sent to some other device that happens to have the same IP on a different network. The decision is remembered and checked again only when your network changes, your Mac wakes from sleep, or a request fails. It doesn't use the Wi-Fi name, which needs Location permission and doesn't work on Ethernet.

If you rename your server, use **Reset** next to "Server identity" in Settings → Connection.

## Where clicks go

**Containers** open, in this order:
1. **Your override** (Settings → Links): any URL, opened exactly as written. Use it for reverse proxies and tunnels.
2. **The container's WebUI setting from its Unraid template**, the same one Unraid's own WebUI button uses. `[IP]` becomes the address you're connected through, and `[PORT:n]` becomes the public port your server mapped to container port `n`.
3. **Otherwise the lowest published TCP port.** This is a generic fallback and can't be right for every container.
4. Otherwise there is no link, and the arrow is dimmed with a tooltip.

Containers on a custom network with their own IP (for example `br0`) can't be reached through the server's address; use an override.

**VMs** open their VNC console when the VM is running and you've set its console port in **Settings → Links**. Unraid's API doesn't report that port: open the VM's console in Unraid and copy the number from the address (`…/wsproxy/5700/`). Unraid assigns these when a VM starts, so a VM's port can change if VMs start in a different order. Without a port, or when the VM isn't running, a click opens Unraid's VMs page.

## Security and privacy

- The API key lives only in the Keychain (this device only, not iCloud) and is never logged or written to the cache.
- MenuRaid contacts **only** the addresses you enter, with one optional exception: **Settings → Display → Check for Unraid OS updates** (off by default). When you turn it on, MenuRaid asks Unraid's public release server (`releases.unraid.net`) for the latest stable version about every 6 hours and compares it with your server's. That request carries nothing about your server: no version, hostname or API key. There is no analytics and no other network traffic.
- **HTTPS with a self-signed certificate:** the first time, MenuRaid shows the certificate's SHA-256 fingerprint and asks you to confirm it (trust on first use). After that it accepts only that exact certificate. If it changes, the connection is blocked with a clear warning and a deliberate re-trust step. There is no "trust any certificate" option.
- **macOS App Transport Security:** home servers usually speak plain `http://`, and macOS blocks that by default for names like `tower.tailnet-xxxx.ts.net`. MenuRaid therefore sets `NSAllowsArbitraryLoads` in its Info.plist. This only widens what the app is *allowed* to connect to; the app still contacts nothing but the addresses you enter. (`NSAllowsLocalNetworking` is deliberately not set: macOS ignores `NSAllowsArbitraryLoads` whenever it is present.) If you build your own copy, keep that setting or `http://` addresses other than IPs and `.local` names won't connect.
- **Plain `http://` on your LAN** sends the API key unencrypted across your network. MenuRaid shows a one-time, dismissible notice and suggests enabling HTTPS in Unraid (Settings → Management Access). It doesn't warn about the remote address, which is normally a VPN such as Tailscale.
- Saved data (a snapshot of the last good state, so the panel isn't empty at launch) is kept in the app's Application Support folder. It can contain your server's hostname and container names, but never the API key.

## When something's wrong

- **Panel greyed, "Saved data":** you're looking at the last snapshot while MenuRaid reconnects.
- **"Disconnected" card:** when nothing gets through for two refreshes in a row, the panel replaces the data cards with one explanation of what went wrong, the server address(es) it's trying (click one to open it in your browser), Retry, and the raw error. The last data stays available, greyed, under "Show last known data".
- **"Blocked by macOS":** macOS refused a plain `http://` address. See the App Transport Security note above, or use `https://`.
- **"The server rejected your API key":** create a new key with at least the Viewer role and save it again.
- **One section shows an error:** each section loads independently, so the rest keeps working. The message says why.
- **Nothing connects away from home:** check the remote address with **Test connection**, and that your VPN is up.
- **"Launch at login" needs approval:** macOS may ask you to approve it in System Settings → General → Login Items.

## Building

Open `MenuRaid.xcodeproj` in Xcode and run the `MenuRaid` scheme. There are no third-party dependencies: only Apple frameworks (SwiftUI, Charts, Network, Security, ServiceManagement, CryptoKit).

The unit tests (Swift Testing) cover address parsing, link building (containers, VM consoles), health rules, route selection with a mock prober, connection reports, decoding of sample server responses (a real capture, scrubbed of personal details), the snapshot cache and the settings.

Before sharing a build, set the bundle identifier to your own (Target → General), and fill in the *Privacy - Local Network Usage Description* and *App Category* fields on the target's Info tab: the build settings for both are present but empty, and macOS shows the first one in a permission prompt.

The sample data used by previews and tests lives in a debug-only Swift file (`Fixtures/FixtureJSON.swift`), so nothing from it is bundled into a release build.

## Limits of version 1

- Read-only: no start/stop/restart.
- One server.
- No network throughput, CPU/motherboard temperatures or fan speeds; the Unraid API doesn't provide them.
- Field names in Unraid's API can differ between versions. MenuRaid decodes leniently, so a missing field blanks only that item, but it has been tested against Unraid 7.2.3 only.

## Design

`UnraidClient` (an actor) does the GraphQL requests and certificate pinning. `RouteManager` and `RouteResolver` choose between the LAN and remote address. `ServerStore` runs the refresh loop, keeps the snapshot and works out health with the pure `HealthEvaluator`. `LinkBuilder` builds every link the panel opens. All code was written from scratch for this project.

## Licence

MIT, copyright (c) 2026 Kyle Reid. See [LICENSE](LICENSE).

MenuRaid is an independent project and is not affiliated with Lime Technology, Inc. "Unraid" is their trademark.
