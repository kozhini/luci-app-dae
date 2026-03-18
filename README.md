# luci-app-dae

LuCI app for [dae](https://github.com/daeuniverse/dae) — eBPF-based Linux high-performance transparent proxy.

Tested on ImmortalWrt 24.10 / GL.iNet MT6000 (arm64).

## Features

- Service status and control (Start / Restart / Stop / Enable / Disable)
- Config editor (`/etc/dae/config.dae`) with Save & Reload
- **Update dae binary** — downloads latest release via installer script, inline progress
- **Update Geo databases** — updates GeoIP + GeoSite, inline progress
- Live log viewer with auto-scroll and Clear button

## Requirements

- `dae` package installed (provides `/etc/init.d/dae`, `/usr/bin/dae`)
- `curl`, `ca-bundle` for update functionality

## Installation

Download the latest `.ipk` from [Releases](../../releases) and install:

```sh
opkg install /tmp/luci-app-dae_0.3.21-1_all.ipk
```

Or force-downgrade if official repo package is installed:

```sh
opkg install --force-downgrade /tmp/luci-app-dae_0.3.21-1_all.ipk
```

Open **Services → dae** in LuCI.

## Build IPK (no buildroot needed)

```sh
git clone https://github.com/YOUR_USERNAME/luci-app-dae
cd luci-app-dae
sh build.sh        # → dist/luci-app-dae_0.3.21-1_all.ipk
```

Requires: `sh`, `python3`, `tar`.

## sysupgrade

Add to `/etc/sysupgrade.conf` to keep dae config and binary across upgrades:

```
/usr/bin/dae
/usr/share/dae
/etc/dae
```

## File structure

```
Makefile                                     OpenWrt buildroot integration
build.sh                                     Manual IPK builder
root/
  etc/dae/config.dae                         Default config (edit before use)
  etc/uci-defaults/90_dae                    UCI init
  usr/libexec/rpcd/luci.dae                  RPC backend
  usr/share/dae/installer.sh                 dae + geo installer/updater
  usr/share/luci/menu.d/luci-app-dae.json    LuCI menu entry
  usr/share/rpcd/acl.d/luci-app-dae.json     ACL permissions
www/
  luci-static/resources/dae/
    status.js                                Status widget + control buttons
    log.js                                   Log viewer
  luci-static/resources/view/dae/
    overview.js                              Main view
```

## License

AGPL-3.0
