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
opkg install /tmp/luci-app-dae_0.3.50-1_all.ipk
```

Open **Services → dae**, click **Update dae**, wait for completion, reload the page.  
Then click **Update Geo databases**, edit config, click **Save**.

## If dae is installed from repository

Works as-is. The installer will not overwrite `/etc/init.d/dae` if it already exists.  
Use **Update dae** button to upgrade the binary independently of opkg.


<img width="1074" height="526" alt="Screenshot 2026-03-20 005702" src="https://github.com/user-attachments/assets/3a539e32-65e7-477f-8ee0-3c2e65f9a685" />


## License

AGPL-3.0
