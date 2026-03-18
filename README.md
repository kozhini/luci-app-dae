# luci-app-dae

LuCI app for [dae](https://github.com/daeuniverse/dae) — eBPF-based Linux high-performance transparent proxy.

Tested on ImmortalWrt 24.10.5 / GL.iNet MT6000 (arm64).

## Features

- Service status and control (Start / Restart / Stop / Enable / Disable)
- Config editor (`/etc/dae/config.dae`) with Save & Reload
- **Update dae binary** — downloads latest release via installer script, inline progress
- **Update Geo databases** — updates GeoIP + GeoSite, inline progress
- Live log viewer with auto-scroll and Clear button

Be careful, huge memory consumption.

## License

AGPL-3.0
