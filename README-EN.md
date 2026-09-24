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

## What's new in v1.3

No new features. **This release is a refactor.** Nothing was removed, half the duplicated
code is gone.

### 1. Shared library extracted (the big one)

v1.2's problem: the same property block was written twice (`post-fs-data.sh` and
`service.sh`), the charging block twice, and battery reading/formatting plus `chkv()`
were copy-pasted three ways across `status.sh` / `gen_status.sh` / `action.sh`.
Changing one value meant editing four files — and missing one meant "I changed it, why
isn't it taking effect?"

Now:

```
lib/common.sh     property writes / battery reading+formatting / settings fallback / node parsing
lib/prop.list     the property manifest (plain text table, single source of truth)
lib/dns-guard.sh  GitHub dynamic DNS guardian (freed from a nested-quote shell string)
```

| | v1.2 | v1.3 |
|---|---|---|
| Places properties are defined | 3 | 1 (`lib/prop.list`) + `system.prop` |
| Charging write blocks | 2 | 1 function |
| Battery formatting functions | 3 | 1 |
| Battery sysfs probing | 3 | 1 |
| `chkv` helpers | 3 | 1 |
| Total script lines | ~1070 | ~800 (with more features and more comments) |

### 2. Robustness fixes

| Problem | v1.2 | v1.3 |
|---|---|---|
| `resetprop` missing | all properties silently fail | falls back to `setprop`, logged |
| Property writes | blind 40+ writes every boot | **read-then-write**; `persist.*` hits disk on every write |
| Charging node parse | raw arithmetic on possibly-empty output | `node_int()` returns empty for non-numeric, callers check |
| Negative/empty battery temp | could render `3.-5` | sign handled explicitly |
| `service.sh` re-entry | settings written twice, two DNS guardians | `.run.lock` guard |
| DNS guardian liveness | `pgrep` on the ping string (false negatives) | pidfile + `/proc/<pid>` check |
| DNS guardian code | inline `nohup sh -c '...'` quote soup | standalone `lib/dns-guard.sh` |
| Uninstall leftovers | properties only; guardian kept running | kills guardian, clears state |
| Empty status values | blank rows (looks broken) | shows `—` |
| Status iframe caching | browser served stale page | timestamped reload on tab switch |
| Version string | hardcoded in 5 files | read from `module.prop` |

### 3. Closed a v1.2 gap

Four 
o.* telemetry-related properties (`ro.hsc.statistics` / `ro.hsc.iot` /
`add.salesservices.register` / `ro.soter.support`) plus `persist.logd.*` and
`af.resampler.quality` were only written in `system.prop` in v1.2, **without ever going
through `resetprop`** — if the system rewrote them, nothing re-applied them. They are now in`lib/prop.list` like everything else.

> This is the only behavior change in this release, and it hardens the telemetry shutdown.

### 4. Copy rewritten

Install banner, Action report, all three WebUI tabs, FAQ, and failure messages were
rewritten with the fish's own voice. **Not one piece of technical information was
dropped** — the accumulated gotchas stay documented, because they will bite again.

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
Action button), **Help** (11 self-service fixes), **About** (info, red lines, hardware limits).

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
