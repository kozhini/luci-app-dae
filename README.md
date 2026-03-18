# luci-app-dae

LuCI app for [dae](https://github.com/daeuniverse/dae) — eBPF-based Linux high-performance transparent proxy.

Tested on ImmortalWrt 24.10 / GL.iNet MT6000 (arm64).

## Features

- Service status and control (Start / Restart / Stop / Enable / Disable)
- Config editor with **Validate** and **Save** buttons
- **Update dae binary** — downloads latest release, installs init.d if missing
- **Update Geo databases** — updates GeoIP + GeoSite with last-updated timestamp
- Live log viewer with auto-scroll and Clear button
- Log size limited to 1MB (circular buffer)

## Installation (clean system, no dae required)

```sh
opkg update
opkg install curl ca-bundle
opkg install /tmp/luci-app-dae_0.3.32-1_all.ipk
```

Open **Services → dae**, click **Update dae**, wait for completion, reload the page.  
Then click **Update Geo databases**, edit config, click **Save**.

## Upgrade from previous version

```sh
opkg install /tmp/luci-app-dae_0.3.32-1_all.ipk
```

## If dae is installed from repository

Works as-is. The installer will not overwrite `/etc/init.d/dae` if it already exists.  
Use **Update dae** button to upgrade the binary independently of opkg.

<img width="959" height="901" alt="Screenshot 2026-03-19 003442" src="https://github.com/user-attachments/assets/1d545592-229b-4655-9c3d-5ac884c77de5" />



## License

AGPL-3.0
