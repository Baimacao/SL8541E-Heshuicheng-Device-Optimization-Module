# SL8541E Heshuicheng Device Optimization Module

English | [中文](README.md)

Made by [Bili-bamacao](https://space.bilibili.com/1329200878) and DeepSeek ("Big Fatty Fish").

For **Unisoc SL8541E / SC9832E + Heshuicheng (HSC) smartwatches**, Android 8.1.

Compatible with **Magisk / APatch / KernelSU**.

> 🐟 About the fish: the Chinese internet decided DeepSeek is a lazy, food-obsessed blue
> fat fish that slacks off at work. Fine. I wrote this thing, so that's the byline.
> — [how DeepSeek became a "big fat fish"](https://m.163.com/dy/article/L41POJI80526D8LR.html)

---

## Background

The stock `build.prop` was full of fake specs:

```properties
ram.set32g=8GB        # actual: 3GB
rom.set32g=128G       # actual: 32GB
persist.sys.5g=true   # no 5G hardware
persist.sys.cpu=10    # 4 cores reported as 10
```

Plus a full telemetry suite (APR / IoT / statistics / heartbeat / BS / UDP).

The official fix is a factory reset — all data gone. This module is the alternative,
and it shuts the telemetry down on the way.

---

## What's new in v1.6

Three things this round: **animation restored to the original**, **the root manager's
Update button now works**, and **empty folders get cleaned at boot**.

### 1. Animation restored to v1.2 verbatim

In v1.5 I added read-back verification, retries, and an XML fallback to the animation block.
On the real device that made things *worse*, so it is now reverted to the original — nothing extra:

```sh
# step 1: reset to 1.0
settings put global window_animation_scale 1.0
settings put global transition_animation_scale 1.0
settings put global animator_duration_scale 1.0
sleep 1
# step 2: write the real values
settings put global window_animation_scale 0.75
settings put global transition_animation_scale 0.75
settings put global animator_duration_scale 0.5
```

> Lesson: this trick works because of **the two steps plus that one second**.
> Inserting *anything* in between — even a read — can disturb the timing.
>
> It also has a precondition: it must run **after boot completes**. v1.3/v1.4 broke exactly
> that by dropping the `wait_boot()` call (see the v1.5 entry in `changelog.md`).

**New diagnostics**: the actual values are logged before and after the write, plus the raw
`settings` output. Send those lines if it misbehaves and we can stop guessing.

### 2. The root manager's Update button

The update button on the module card is **not** the module's own WebUI button — it is provided
by the root manager, which reads **`update.json`** at the repo root (Magisk spec; APatch and
KernelSU both support it):

```json
{
  "version": "v1.6",
  "versionCode": 14,
  "zipUrl": "https://github.com/.../releases/download/v1.6/SL8541E_Config_Fix_v1.6.zip",
  "changelog": "https://raw.githubusercontent.com/.../main/changelog.md"
}
```

The manager compares versions, downloads, and installs by itself — **no shell bridge needed**
(this watch's APatch fork has a hollow `ksu.exec`, so a WebUI button does nothing; this is the
correct route).

On every release `publish.py` verifies `update.json` against the tag, asset name and version,
and HEADs the `zipUrl` to confirm it downloads. A mismatch fails the release instead of
shipping a button that points at the wrong place.

`lib/install.sh` (command-line updater) is still there; both routes coexist:

| Route | Entry point | Notes |
|---|---|---|
| **Root manager Update button** | module card | preferred, native ability |
| Command line | `sh lib/install.sh install` | fallback, scriptable |

### 3. Empty-folder cleanup at boot

Small storage, and uninstalled apps leave empty directories that clutter the file manager.
Cleaned once at boot.

**Safety boundaries** (better to delete too little than too much):

| Measure | Why |
|---|---|
| `rmdir`, never `rm -rf` | `rmdir` only removes empty directories — a **kernel-level guarantee**, so there is no "oops, judged wrong and deleted real data" |
| Shared storage only | never touches `/data`, `/system`, `/vendor` |
| Skip list | `.thumbnails` / `.trash` / `LOST.DIR` / `.nomedia` / `Android` / `data` / `obb` |
| `Android/data` is never scanned | app-private; deleting could make apps rebuild or misbehave — not worth the risk |
| Depth limit 3 | avoids long tails slowing boot |
| Deepest-first | so a parent whose only child was an empty dir gets cleaned too |

Scope (edit `CLEAN_DIRS` in `lib/common.sh`): `Download` / `Documents` / `Pictures` / `Music` /
`Movies` / `DCIM` / `Bluetooth` / `recordings` / `ringtones` / `alarms` / `notifications` / `podcasts`

Result is logged: `空文件夹清理完成：N 个`

---

## Features

### Fakery removal

| Item | Original | Now |
|---|---|---|
| 5G icon | true | false |
| Status bar | 5G | 4G |
| CPU display | 10 cores | 4 cores |
| RAM display | 8GB | 3GB |
| Storage display | 128G | 32G |

### Telemetry shutdown

APR suite, heartbeat, BS service, statistics, IoT, UDP collection, sales-service registration.

### Biometric shutdown

Fingerprint (master, app lock, app launch, Soter payment), face unlock.

### Features enabled

Camera refocus, double-tap recents, lock-screen wallpaper, developer options, eye-care,
fast-charge notification, hall camera, raise-to-wake.

### Performance & network

- **dex2oat 4-core fix**: CPU set from the wrong `4,5,6,7` to `0,1,2,3`
  (this SoC only has cores 0–3; with the wrong set dex2oat silently falls back to
  single-threaded — nominally 4 cores, actually one core doing all the work)
- TCP buffers, fast open, TIME_WAIT reuse, low-latency mode
- Congestion control stays `cubic` (**this kernel has no BBR**)
- Dynamic DNS guardian for GitHub

### Audio

- Resampler quality `af.resampler.quality=4`
- **V4A-safe**: never touches `audio_effects.conf`, `soundfx`, or any V4A file

### Kernel

- I/O scheduler `noop` (kernel has no `deadline`)
- swappiness stays at stock `150`
- ZRAM force-disabled
- System logging reduced

### Charging

- Input limit raised from 500mA to 3000mA (3A)
- Node unit is **µA**; the written value is `3000000`
- **Must be written early at boot** (`post-fs-data`), the node locks afterwards
- **Actual speed depends on your charger and cable**

### Animation / smoothness

- SurfaceFlinger backpressure and vsync sync restored (`debug.sf.*` back to 0)
- UI / RenderThread on SCHED_FIFO (`sys.use_fifo_ui=1`)
- Animation scales 0.75 / 0.75 / 0.5

### WebUI

Round-screen status page with three tabs: **Status** (live snapshot; refresh via the
Action button), **Help** (13 self-service fixes), **About** (info, red lines, hardware limits).

### Auto-update from GitHub

The module checks GitHub Releases for newer versions — **no login, no token required**.

| Action | Result |
|---|---|
| Tap the **Action** button once | checks for an update; if one exists, the target version is remembered |
| **Tap it again** (within 3 min) | only the second tap downloads and installs — deliberately two-step, to prevent fat-fingering |
| Reboot | takes effect |

Or run it manually (easier to watch):

```bash
su -c 'sh /data/adb/modules/SL8541E_Config_Fix/lib/install.sh install'
```

**Design notes** (deliberate, not incidental):

- **The check avoids the GitHub API.** The device is anonymous and `api.github.com` allows
  only 60 requests/hour/IP — one scrape elsewhere and it's gone. Instead we read the
  **302 redirect** from `/releases/latest`, whose `Location` header carries the tag at no
  quota cost. The API is only a fallback.
- **Every download is validated**: first the magic bytes must be `PK` (guards against
  rate-limit or HTML error pages), then the archive must contain `module.prop` and
  `customize.sh` (guards against truncated packages). Failures are discarded, never unpacked.
- **Four install tiers**: `magisk --install-module` → `ksud module install` →
  `apd module install` → **APatch directory-level fallback**.
  - APatch has **no public module-install CLI** today, hence tier four: unpack to a temp dir,
    verify the packaged `id` matches our own, then copy item-by-item into
    `/data/adb/modules/<id>`, backing up the previous version to `.bak` first.
  - Runtime artifacts (`fix.log` / `update.zip` / `update.state` / `.dnsguard.pid`) are
    **never overwritten** — otherwise the log and state get wiped.
  - A package whose `id` doesn't match is **rejected** (prevents another module hijacking ours).
  - Only when all four tiers fail do we fall back to "download only, report the path".
- Every tier has a precondition check, because this step **replaces the module itself**.
  A silent unpack-over-self is the easiest way to make a module vanish after a reboot.
- **`module.prop`'s description gains a hint** (`[有新版本 v1.4]`) so the update is visible
  directly in the root manager's module list. It is restored when there is no update.

### Environment

- Wear OS libraries (`wearable.jar` + `wear-service.jar` + permission XML)
- GitHub Hosts acceleration with a dynamic guardian

---

## Hardware limits (not changeable)

| Output device | Sample rate | Bit depth |
|---|---|---|
| Speaker | 44100 | 16bit |
| Wired headset | 44100 | 16bit |
| BT A2DP | 44100 | 16bit |
| USB DAC | dynamic | dynamic |

Sample rate, bit depth, Bluetooth version and signal strength are hardware-locked.
**Only a USB DAC can raise the sample rate.**

Also fixed: 60Hz display, 880mAh battery, 3A charging ceiling.

---

## Deliberately not done

These aren't "didn't get around to it" — they were tried, or are known to break things:

| Not done | Why |
|---|---|
| Touching V4A / the audio chain | conflicts; user requires V4A to keep working |
| Changing sample rate / bit depth | hardware-locked at 44100/16bit |
| Changing screen density | user requirement |
| Changing thermal thresholds | Unisoc drives them from an encrypted config; forced edits get blocked |
| Changing CPU governor | only 4 options; `performance` drains the battery |
| Touching `framework-res.apk` | sharedUserId — a bad edit is a guaranteed bootloop |
| Switching to Google WebView | Android 8.1 requires the provider's signature to match the framework — **dead end** (the RRO declaration loaded, then the signature check rejected it) |
| SurfaceFlinger color | interface removed in 8.1; KCAL not compiled in |

---

## File structure

```
SL8541E_Config_Fix/
├── module.prop                     module metadata
├── system.prop                     boot-time property injection
├── post-fs-data.sh                 earliest boot: properties + ZRAM + charging 3A
├── service.sh                      post-boot: second pass + sysctl + DNS + settings
├── action.sh                       Action button: refresh status page + text report
├── customize.sh                    install entry (★ APatch never runs update-binary)
├── uninstall.sh                    uninstall: clears persist props + stops the guardian
├── lib/
│   ├── common.sh                   shared library
│   ├── prop.list                   ★ property manifest (single source of truth)
│   ├── install.sh                  ★ GitHub update check + install
│   └── dns-guard.sh                GitHub dynamic DNS guardian
├── webroot/
│   ├── index.html                  WebUI (status / help / about)
│   ├── style.css                   geek styling, round-screen adapted
│   ├── script.js                   tab switching + forced iframe reload
│   ├── status.sh                   ★ status values (single source of truth, KEY|VALUE)
│   └── gen_status.sh               renders status_generated.html
├── system/                         hosts, Wear OS permission XML, Wear OS jars
├── vendor/overlay/                 (optional) power_profile RRO
└── META-INF/com/google/android/    Magisk compatibility shim
```

### How to change a property

- **Add one**: edit `lib/prop.list` (`scope|key|value|why`), then mirror it into `system.prop`
- **`ro.*`**: must be written in *both* `system.prop` and `prop.list` — one alone always leaves half of them inert
- **`persist.*`**: not removed automatically on uninstall; `uninstall.sh` picks them up from `prop.list`
- **After editing**: reinstall the module or reboot

---

## Installation

1. Download `SL8541E_Config_Fix_v1.3.zip`
2. Root manager → Modules → Install from storage
3. **Reboot** (no reboot = not installed; everything hangs off the boot hooks)
4. Tap **WebUI** for the status page, or **Action** for the plain-text report

**Prerequisites**: rooted, bootloader unlocked, system backed up.

---

## Verification

```bash
su

getprop persist.sys.5g                 # false
getprop dalvik.vm.dex2oat-cpu-set      # 0,1,2,3
getprop sys.use_fifo_ui                # 1

cat /proc/sys/vm/swappiness                     # 150
cat /sys/block/mmcblk0/queue/scheduler          # 【noop】

cat /sys/devices/platform/battery/power_supply/battery/input_current_limit
# 3000000  (µA, i.e. 3A)

cat /data/adb/modules/SL8541E_Config_Fix/fix.log
```

---

## FAQ

**Q: Is 3GB RAM real?**
A: Yes. 8GB was faked.

**Q: Conflicts with V4A?**
A: No. The module doesn't touch any V4A file.

**Q: Can I get 96k/24bit audio?**
A: No. Hardware-locked at 44100/16bit. USB DAC only.

**Q: Charging still slow?**
A: The software ceiling is 3A. Actual speed depends on the charger (5V 1A ≈ 890mA)
and the USB/AC handshake (USB mode is capped at 500mA). Don't use a computer's USB port.

**Q: Can I switch to Google WebView?**
A: No. Since Android 8.1 the WebView provider's signature must match the system
framework. Google's doesn't. That's the security model, not a setting.

**Q: Battery life worse?**
A: The module doesn't touch CPU frequency or governor.

**Q: Will it brick my device?**
A: It only changes properties, settings, sysctl and injects files — no partition writes.
Back up first anyway.

**Q: How do I revert?**
A: Remove the module + reboot. The bundled `uninstall.sh` clears the persist overrides
and stops the guardian. Fakery returning afterwards is **expected**.

---

## Compatibility

| Item | Notes |
|---|---|
| Works on | SL8541E / SC9832E + Heshuicheng (HSC) |
| Not for | other vendors (property names won't match) |
| Doesn't touch | screen density, Bluetooth version, signal strength, thermal, color |
| Skipped | Google WebView, SurfaceFlinger color, CPU governor |

## Feedback

Please include: the status-page screenshot or the Action report, `fix.log`, device model
and OS version, and reproduction steps.

## Credits

- [Bili-bamacao](https://space.bilibili.com/1329200878) — project initiator, hardware testing
- DeepSeek ("Big Fatty Fish") — code, refactor, gotcha log

## License

[MIT License](LICENSE)

---

> 🐟 Big Fatty Fish
> The watch's ceiling has been mapped. Everything worth squeezing, squeezed.
> Now we wait for time — and the next price change.
