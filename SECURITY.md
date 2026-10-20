# Security policy

MenuRaid holds an Unraid API key and talks to your server, so security reports are taken seriously.

## Supported versions

Only the [latest release](https://github.com/TankyTom/MenuRaid/releases/latest) gets fixes. Please check you can reproduce the problem on it before reporting.

## Reporting a vulnerability

**Please don't open a public issue for a security problem.** Report it privately instead:

1. Go to the repository's [**Security** tab](https://github.com/TankyTom/MenuRaid/security).
2. Choose **Report a vulnerability**.

Please include:

- what you found and why it matters (for example "the API key is sent to X when Y");
- the steps to reproduce it;
- your MenuRaid version, macOS version and Unraid version.

**Please remove anything private before you send it:** your real API key, your server's name and addresses, and your container and VM names. Placeholders such as `192.168.1.10` and `tower` are fine.

This is a small project looked after by one person, so there's no guaranteed response time, but reports are read and acknowledged on a best-effort basis. If you'd like credit when a fix is released, say so in the report.

## What counts

Examples of things worth reporting:

- the API key being sent, logged or stored anywhere it shouldn't be, including to a different host or in a redirect;
- a way to get MenuRaid to trust a certificate it shouldn't, or to skip the certificate pin;
- a way to make MenuRaid open a link you didn't intend;
- the app contacting an address you haven't entered, other than the two opt-in update checks described in the README.

## What doesn't

- Plain `http://` being allowed. It's deliberate, because home servers usually use it, and the app warns about it. See [Security and privacy](README.md#security-and-privacy) in the README for how the API key is protected and where that protection stops.
- Problems that need access to your Mac account or your unlocked Keychain.
- Vulnerabilities in Unraid itself. Please report those to [Unraid](https://unraid.net).

The README's [Security and privacy](README.md#security-and-privacy) section describes the design and its limits in detail.
