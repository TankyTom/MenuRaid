# Changelog

## 1.0.0

First release.

- Menu bar status symbol (check, triangle or octagon) with a value you choose: CPU %, RAM %, hottest disk temperature, or icon only.
- Panel with health reasons, system (CPU and RAM sparklines, uptime, Unraid version), array and disks, Docker containers and VMs.
- Click a container for its web UI, or a VM for its VNC console.
- LAN and remote addresses, with automatic switching when your network changes.
- HTTPS with trust-on-first-use certificate pinning for self-signed certificates.
- Optional macOS notifications for new problems, and optional update hints for Unraid OS, containers and MenuRaid itself (checked against GitHub releases).
- Your API key isn't sent to a plain-HTTP LAN address until its login page names your server, and redirects to another host are refused.
- Read-only: it never changes anything on your server.

Tested against Unraid 7.2.3 only.
