<div align="center">

# Band Viewer

**Run Xiaomi Lua watchfaces in your browser: Mi Band 10 Pro, 9 Pro, 8 Pro, Band 10, Band 9, Redmi Watch 4 and 6, Watch S3 and S4.**
Drop in a `.face`, tap it, long-press it and feed it fake health data, all before it ever touches your wrist.

[![Devices](https://img.shields.io/badge/devices-9%20Xiaomi%20bands%20%26%20watches-c6f432?style=flat-square)](#devices)
[![Needs](https://img.shields.io/badge/needs-Python%203%20only-38d6f5?style=flat-square)](#quick-start)
[![Deps](https://img.shields.io/badge/dependencies-none-ff9f0a?style=flat-square)](#how-it-works)
[![License](https://img.shields.io/badge/license-MIT-af82ff?style=flat-square)](LICENSE)

### [▶ Open Band Viewer in your browser](https://hassan-xsf.github.io/band-viewer/)

<img src="docs/viewer.png" alt="Band Viewer running the Stride watchface" width="100%">

</div>

## Why

Testing a watchface on the band means building it, sending it to your phone, installing it over Bluetooth, selecting it,
and hoping it doesn't lock you out. Band Viewer cuts that down to **save → look**.

## Features

- **9 devices**: real screen size and shape (rounded, narrow or round). Faces named `*_<device>.face` pick their device by themselves
- **Runs online or locally**: the online version has samples and takes any `.face` you drop on it
- **Hot reload** (local): drop `.face` files in `faces/`, and they reload by themselves when rebuilt
- **Real input**: click = tap, hold = long-press, Space = tap the centre
- **Fake band data**: time, date, battery, steps, heart rate, calories, SpO₂, sleep, weather, charging, Bluetooth, DND
- **Switch check**: warns if a face grabs every touch and would trap you on the band
- **Inspect**: every file inside the `.face`, the `main.lua` source, and a console with `print()` output and Lua errors
- **Persistent storage**: `/data` writes survive reloads, like on the band. One click clears them.
- **Save PNG**: a screenshot at the device's size, ready to use as the face's `preview.png`
- **FPS, Lua ms per frame and object count**, so you can spot slow faces early

## Quick start

**Online:** open **[hassan-xsf.github.io/band-viewer](https://hassan-xsf.github.io/band-viewer/)**, then drop a `.face` on it
or try one of the samples. Nothing is uploaded: the face runs entirely in your browser.

**Locally**, for hot reload while you build faces:

```bash
git clone https://github.com/hassan-xsf/band-viewer
cd band-viewer
python serve.py        # or double-click start.bat on Windows
```

It opens `http://127.0.0.1:8770` and serves only on your own machine. Drop a `.face` into `faces/`, onto the page, or onto `start.bat`.

Need faces to try? Grab some from **[Mi Band 10 Pro Faces](https://github.com/hassan-xsf/miband10pro-faces)**.

## Devices

<img src="docs/devices.png" alt="Faces running on Watch S3, Redmi Watch 4 and 6, Band 9 and Band 10" width="100%">

| Device | Screen | | Device | Screen |
|---|---|---|---|---|
| Mi Band 10 Pro / 9 Pro / 8 Pro | 336 × 480 | | Redmi Watch 4 | 390 × 450 |
| Mi Band 10 | 212 × 520 | | Redmi Watch 6 | 432 × 514 |
| Mi Band 9 | 192 × 490 | | Xiaomi Watch S3 / S4 | 466 round |

Pick one from **Device** at the top. Screen sizes come from the EasyFace device database.

## How it works

The browser unpacks the `.face` itself. `main.lua` runs on [fengari](https://fengari.io), a Lua VM written in
JavaScript. [`lvgl_shim.lua`](lvgl_shim.lua) provides the band's `lvgl` (luavgl) and `dataman` APIs on a canvas: objects,
images, labels, flags, events, timers, `pageOnPause`/`pageOnResume` and data subscriptions.
`serve.py` is about 80 lines of stdlib Python that lists the faces and serves them.

```
faces/*.face ──► serve.py ──► index.html ──► fengari (Lua) + lvgl_shim ──► <canvas> 336×480
```

## Limits

It's an emulator, not the band. Fonts, timing and a few less common widgets differ slightly, and native (C) apps don't
run. Always do a final check on the real band.

## Troubleshooting

**Faces fail to load / `ERR_CONNECTION_RESET`.** Your antivirus web shield (Avast, AVG and others) is scanning local HTTP
traffic and cutting large downloads. Add an exception for `http://127.0.0.1:8770`, or turn off HTTP scanning for local
addresses.

**Port 8770 is busy.** A viewer is probably already running. `serve.py` just opens the existing one.

## Credits

- [fengari](https://github.com/fengari-lua/fengari-web) (MIT): Lua in the browser
- [m0tral](https://github.com/m0tral): his [Lua watchface examples](https://github.com/m0tral/MiWatchLuaWatchfaces) and
  [EasyFace](https://github.com/m0tral/EasyFace) compiler documented the band's Lua API and `.face` format this emulates
- MiSans font: Xiaomi (MiSans license)
- Flappy Bird sample: game by Dong Nguyen (.GEARS); sprites from
  [samuelcust/flappy-bird-assets](https://github.com/samuelcust/flappy-bird-assets) and
  [mrspeaker/wafty-man](https://github.com/mrspeaker/wafty-man). Art belongs to its owners, personal use only

## License

[MIT](LICENSE) © Hassan Shakil
