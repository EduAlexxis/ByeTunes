# ByeTunes Hosted Backend Terms

*Last updated: October 10, 2026*

The ByeTunes **source code** is released under the [MIT License](LICENSE). The **official ByeTunes backend**, the download and metadata server run by the maintainer, is a separate hosted service. It is **not** part of the MIT-licensed code, and access to it is not granted by the MIT License.

## In short

| You may | You may not |
| --- | --- |
| Use the official app with the official backend | Point a modified, forked or repackaged build at the official backend |
| Modify ByeTunes for yourself | Extract the official server URL, configuration or credentials from official releases |
| Distribute your modified version under the MIT License, with its source open and your changes documented, using your own backend | Scrape, load-test or run automated traffic against the official backend |
| Re-upload an identical, unmodified official release, if people can verify where it came from | Present a modified build as the official app |

## Using the official backend

1. **Official, unmodified builds only.** The official backend is provided for the official ByeTunes app as published in this repository's releases. Signing or sideloading an unmodified official build yourself is fine.
2. **Modified builds need their own backend.** If you modify, fork, repackage or embed ByeTunes, host your own backend and point your build at it. Do not use the official backend from a build that differs from the official release.
3. **No extraction of server configuration.** Do not extract the official server URL, configuration or credentials from official releases (for example from `Config.plist`) to bundle them in another app or tool.
4. **No automated or abusive use.** Do not scrape, load-test or otherwise generate automated traffic against the official backend.
5. **Access may be limited or blocked at any time.** The maintainer may rate-limit, change, restrict or shut down the backend, or block any client or build, without notice and without liability. The service is provided as is, with no uptime guarantee.

## Sharing ByeTunes

- **Linking is preferred.** Please link to this repository's [releases](https://github.com/EduAlexxis/ByeTunes/releases) instead of hosting copies.
- **Identical unmodified copies are allowed.** You may re-upload an official release without changes, as long as it is clearly the same build and others can verify it came from this repository, for example by linking to the release it was taken from.
- **Modified versions are allowed under the MIT License.** You may distribute them if the source is open, your changes are documented, and the original license and copyright notice are kept. They must use their own backend, and they must not claim to be the official ByeTunes app.

## Your responsibility for what you download

ByeTunes and its backend are tools. You are solely responsible for the content you search for, download, store and use with them, and for making sure you have the right to do so under the copyright laws and the terms of any service that apply to you. The maintainer does not host, own or license that content, and is not responsible for how you use these tools.

## Running your own backend

You are responsible for any backend you host, including the accounts, credentials and third-party services it uses, and for complying with their terms and with applicable law.

## Questions

Open an issue on [GitHub](https://github.com/EduAlexxis/ByeTunes/issues) or ask in the [Discord](https://discord.gg/dDQ4P4SyKJ).
