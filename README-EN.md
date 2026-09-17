# SL8541E Heshuicheng Device Optimization Module

> A system-level optimization module made by a DeepSeek instance nicknamed "Big Fatty Fish" and Bili-creator Baimacao, for a white-label smartwatch.
> Not a ROM, not a firmware, just a Magisk / APatch / KernelSU module.

---

## 📖 Table of Contents

- [1. What Is This](#1-what-is-this)
- [2. Why Build This](#2-why-build-this)
- [3. Hardware Platform Analysis](#3-hardware-platform-analysis)
- [4. Feature List](#4-feature-list)
- [5. Technical Rationale](#5-technical-rationale)
- [6. Pitfalls Encountered](#6-pitfalls-encountered)
- [7. File Structure](#7-file-structure)
- [8. Installation](#8-installation)
- [9. Verification](#9-verification)
- [10. FAQ](#10-faq)
- [11. Disclaimer](#11-disclaimer)

---

## 1. What Is This

A system optimization module for smartwatches based on **Unisoc SL8541E / SC9832E platform**, **Heshuicheng (HSC) solution**.

It does four categories of work:

1. **Strip vendor fakery** — kill fake 5G icons, fake CPU core counts, fake RAM/storage capacities
2. **Disable data harvesting** — silent APR reporting, heartbeats, IoT cloud, telemetry services
3. **Restore missing capabilities** — developer options, double-tap recents, lock-screen wallpaper, Wear OS libraries, TCP tuning, 4-core dex2oat
4. **System-level fine-tuning** — audio resampler quality, kernel low-jitter parameters, animation scaling

**It's not a miracle worker**. This watch's hardware ceiling is what it is. This README will honestly tell you what's possible, what isn't, and why.

---

## 2. Why Build This

When this watch first arrived, the `build.prop` was full of absurd numbers:

```properties
ram.set32g=8GB        # actual: 3GB
ram.set32g.true=2GB   # even the "true" value was faked to 2G
rom.set32g=128G       # actual: 32GB
persist.sys.5g=true   # no 5G hardware exists
persist.sys.cpu=10    # 4 cores reported as 10
persist.sys.logo=5G   # status bar shows 5G icon
persist.sys.rom.fake=1
ro.hsc.fake_romram=true
```

Alongside this was a full suite of data harvesting:

```properties
persist.sys.apr.enabled=1
persist.sys.apr.autoupload=1
ro.hsc.statistics=true
ro.hsc.iot=true
```

This isn't vendor negligence — it's **deliberate**. Fake numbers make the spec sheet look better. Silent telemetry collects user data.

So this module was born: tear off the disguise, kill the phoning home, restore the features that should have been there.

---

## 3. Hardware Platform Analysis

To optimize a device, you first need to know its ceiling.

### 3.1 SoC

| Item | Value |
|---|---|
| Model | Unisoc SC9832E (SL8541E is its package variant) |
| CPU | 4× ARM Cortex-A53, up to 1.4 GHz (down to 768 MHz) |
| Architecture | arm64-v8a (with armeabi-v7a support) |
| Process | 28nm |
| Class | Entry-level 4G watch / feature phone |

Quad-A53 is a 2014-era core. Performance is weak. That's why this module **doesn't chase performance** — it just stops power-saving policies from strangling the hardware.

### 3.2 Audio Subsystem

Real capabilities extracted from `dumpsys media.audio_policy`:

| Output Device | Max Sample Rate | Bit Depth | Channels |
|---|---|---|---|
| Speaker | **44100 Hz** | 16 bit | Stereo |
| Wired Headset | **44100 Hz** | 16 bit | Stereo |
| BT A2DP Out | **44100 Hz** | 16 bit | Stereo |
| USB DAC | Dynamic (device-dependent) | Dynamic | Dynamic |

**Conclusions**:

- Primary output is **locked at 44100 Hz / 16 bit**
- Bluetooth is also 44100 Hz
- Want 48000 Hz or 24-bit? HAL will refuse
- **The only path to high sample rate is a USB DAC**

So any dream of "raising sample rate/bit depth" on this watch is fantasy. What's achievable:
- More precise resampling (48000 → 44100 downconversion loss)
- More stable audio writes (lower jitter)

### 3.3 Audio Codec

From `tinymix`:

```
Mixer name: 'sprdphone'
Number of controls: 131

VBC DA EQ Switch          On
VBC DA EQ Profile Select  3
DACL DG Set               24
DACR DG Set               24
```

- Codec is Unisoc's own VBC
- Built-in hardware EQ path (`VBC DA EQ Switch=On`)
- DAC gain default 24

This tells us: **there's a hardware EQ in the audio path**, but default tuning is already done — don't touch it.

### 3.4 Storage and I/O

```
/dev/block/mmcblk0/queue/scheduler: noop [cfq]
```

- eMMC flash
- Kernel **supports only `noop` and `cfq`**
- **No `deadline`** (many online tutorials tell you to use deadline — not supported here)

This matters. My early versions erroneously wrote `echo deadline`, it silently failed, and the system stayed on cfq.

### 3.5 Kernel

- Unisoc custom kernel, Linux 4.x base
- `swappiness` default **150** (abnormally high; Linux default is 60)
- `tcp_congestion_control` supported (defaults to `cubic`)
- **BBR not compiled in** (many "network optimization" guides tell you to enable BBR — unavailable here)

---

## 4. Feature List

### 4.1 Fakery Removal

| Item | Original | Current |
|---|---|---|
| 5G icon | `true` | `false` |
| Status bar label | `5G` | `4G` |
| CPU core display | `10` | `4` |
| RAM display | `8GB` | `3GB` |
| Storage display | `128G` | `32G` |
| Master fake switch | `true` | `false` |

### 4.2 Telemetry Shutdown

| Service | Property | Current |
|---|---|---|
| APR reporting | `persist.sys.apr.enabled` | `0` |
| APR auto-upload | `persist.sys.apr.autoupload` | `0` |
| APR report level | `persist.sys.apr.reportlevel` | `0` |
| APR interval | `persist.sys.apr.intervaltime` | `0` |
| Heartbeat | `persist.sys.heartbeat.enable` | `0` |
| BS service | `persist.sys.bsservice.enable` | `0` |
| Statistics | `ro.hsc.statistics` | `false` |
| IoT cloud | `ro.hsc.iot` | `false` |
| UDP data collection | `persist.sys.start_udpdatastall` | `0` |
| Sales service register | `add.salesservices.register` | `false` |

### 4.3 Biometric Shutdown

| Item | Property | Current |
|---|---|---|
| Face unlock | `heils.facelock` | `0` |
| Fingerprint master | `persist.support.fingerprint` | `false` |
| FP app lock | `persist.sprd.fp.lockapp` | `false` |
| FP app launch | `persist.sprd.fp.launchapp` | `false` |
| WeChat Soter payment | `ro.soter.support` | `false` |

**Why disable fingerprint**: this watch's FP sensor is imprecise, high false-rejection rate, worse than a PIN. Off = more power saved.

### 4.4 Features Enabled

| Item | Property |
|---|---|
| Camera refocus | `persist.sys.cam.refocus.enable=true` |
| Double-tap recents | `ro.config.f14_double_click_recent_tasks=true` |
| Lock-screen wallpaper | `ro.lockwallpaper.enable=true` |
| Developer options | `settings put global development_settings_enabled 1` |
| Eye-care mode | `ro.dipaly.eyecare=1` |
| Fast charging | `ro.hsc.fastcharging=true` |
| Hall-effect camera | `hall.switch.camera=true` |
| Raise-to-wake | `ro.config.raise_wakeup_timeout=3000` |

### 4.5 Performance and Network

| Item | Value |
|---|---|
| 4-core dex2oat | `dalvik.vm.dex2oat-cpu-set=0,1,2,3` |
| dex2oat threads | `dalvik.vm.dex2oat-threads=4` |
| TCP buffer | `rmem_max/wmem_max = 8388608` |
| TCP fast open | `tcp_fastopen = 3` |
| TCP congestion | `cubic` |
| TIME_WAIT reuse | `tcp_tw_reuse = 1` |

### 4.6 Audio and Kernel

| Item | Value |
|---|---|
| Audio resampler quality | `af.resampler.quality=4` |
| swappiness | `10` (was 150) |
| I/O scheduler | `noop` |

### 4.7 Wear OS Environment

Injects three files:

```
/system/etc/permissions/com.google.android.wearable.xml
/system/framework/com.google.android.wearable.jar
/system/framework/wear-service.jar
```

This makes the system "aware" of Wear OS libraries, so apps depending on Wear APIs can load them.

### 4.8 Maintenance

- **Boot-time battery stats cleanup**: removes `/data/system/batterystats.bin` etc.
- **Two-step animation fix**: reset to 1.0, then set targets

---

## 5. Technical Rationale

### 5.1 Fakery Removal

**Principle**: Android's `Settings.System` has no "device info" storage. Vendors display RAM/storage through `build.prop` properties that the Settings app reads.

For Unisoc platforms, the Settings app reads:

```properties
persist.sys.ram        # RAM display
persist.sys.rom        # Storage display
persist.sys.cpu        # Core count display
persist.sys.5g         # 5G icon in status bar
persist.sys.logo       # Status bar text
```

Write true values back, and the Settings app displays truth.

**Verification**: `getprop persist.sys.ram` should return `3GB`.

### 5.2 Telemetry Shutdown

**Principle**: Vendor telemetry is controlled by `persist.sys.apr.*` — the **APR (Android Problem Reporter)** module, a Unisoc-developed exception reporting framework that periodically collects device info, crash logs, usage patterns, encrypts and uploads them.

| Property | Purpose |
|---|---|
| `persist.sys.apr.enabled` | Master switch |
| `persist.sys.apr.autoupload` | Auto-upload (else local only) |
| `persist.sys.apr.reportlevel` | Report verbosity |
| `persist.sys.apr.intervaltime` | Reporting interval |
| `persist.sys.apr.lifetime` | Data retention duration |
| `persist.sys.apr.exceptionnode` | Whether to report crash nodes |

All set to 0/false silences APR.

### 5.3 dex2oat 4-Core Fix

**Discovery**:

The device had a `dex2oat_4t` module with:

```properties
dalvik.vm.dex2oat-cpu-set=4,5,6,7
```

That's an **8-core layout**. But SL8541E has **only 4 cores** (CPUs 0,1,2,3).

This means dex2oat can't find CPUs 4–7 and **silently fails or falls back to single-thread**. The original module was not only useless, it might have slowed compilation.

**Fix**: change to `0,1,2,3` so dex2oat actually uses all 4 cores.

**Principle**: `dalvik.vm.dex2oat-cpu-set` is a **CPU affinity mask** passed to the ART VM, comma-separated CPU IDs. ART parses this string and binds compilation threads to those CPUs.

### 5.4 TCP Tuning

**What properties can do**:

```properties
net.tcp.default_init_rwnd=256   # initial receive window
```

Original 60, too small. RWND tells the peer "how much I can receive" during handshake. Too small → slow-start takes too long.

**What needs echo (kernel layer)**:

`/proc/sys/net/*` are **kernel runtime parameters**, not managed by property system. Must be written directly at boot:

```sh
echo 8388608 > /proc/sys/net/core/rmem_max
echo "4096 87380 8388608" > /proc/sys/net/ipv4/tcp_rmem
```

| Parameter | Purpose |
|---|---|
| `rmem_max` / `wmem_max` | Per-socket buffer max |
| `tcp_rmem` | TCP receive buffer (min/default/max) |
| `tcp_wmem` | TCP send buffer (min/default/max) |
| `tcp_fastopen` | TFO, data in SYN |
| `tcp_tw_reuse` | Reuse TIME_WAIT connections |
| `tcp_low_latency` | Prioritize latency over throughput |

**Important**: don't copy `bbr` from online tutorials. This kernel **doesn't have BBR compiled in**. It will fail.

### 5.5 Audio Resampler Quality

**Background**:

Most streaming services (NetEase Cloud, QQ Music, Spotify) output 48000 Hz by default. But this watch's audio HAL only accepts 44100 Hz. So **every playback requires resampling**: 48000 → 44100.

Android's default resampler is mediocre quality. AOSP provides `af.resampler.quality`:

| Value | Algorithm |
|---|---|
| 0 | Off (dangerous, may distort) |
| 1 | Lowest quality, fast |
| 2 | Low quality |
| 3 | Medium quality (default) |
| 4 | High quality |
| 5+ | Extreme quality, CPU-heavy |

Setting to 4 significantly reduces high-frequency loss and phase distortion.

**Why not higher**:

- 5+ strains an A53 too much
- Diminishing returns (4 is already near-transparent)

**Why not touch `audio_effects.xml`**:

Because ViPER4Android is installed. Its config file is `/system/etc/audio_effects.conf` (**not .xml**). The system fails XML load at boot and falls back to .conf. So:

- ❌ Editing .xml does nothing (system doesn't read it)
- ⛔ Editing .conf breaks V4A
- ✅ Only touch `af.resampler.quality`, an AOSP-standard property V4A doesn't use

### 5.6 Lowering swappiness

**What 150 means**:

`swappiness` controls how aggressively the kernel swaps anonymous pages to zram/swap under memory pressure.

- 0: never swap
- 60: Linux default
- 100: aggressive
- 150: extremely aggressive (Unisoc customization)

**Why it affects audio**: high swappiness → frequent page swaps under memory pressure → system jitter → audio threads preempted → **pops/dropouts**.

Lowering to 10 means no swapping unless memory is truly tight. Audio path stays stable.

**Why not 0**: 3GB RAM is not generous. Zero swap could cause OOM kills. 10 is safe.

### 5.7 I/O Scheduler

**Original cfq**:

- `cfq` (Completely Fair Queuing): designed for spinning disks, fair but adds latency
- `noop`: simple FIFO, no reordering, **best for flash**
- `deadline`: compromise to reduce latency jitter

**Why noop**:

1. eMMC has no seek latency — cfq's "fairness" is meaningless
2. noop has lowest latency; audio writes and dex2oat reads are smoother
3. **This kernel doesn't support deadline** (only `noop` and `cfq` available)

### 5.8 Wear OS Library Injection

**What it does**:

```
/system/etc/permissions/com.google.android.wearable.xml  ← declares library
/system/framework/com.google.android.wearable.jar         ← core library
/system/framework/wear-service.jar                        ← service library
```

**Principle**:

Android's `/system/etc/permissions/*.xml` are **permission declaration files**. Using `<library>` or `<feature>` tags, they tell the system "I have this capability".

`com.google.android.wearable.xml` declares Wear OS Java libraries. At boot, the system adds these jars to app classpaths. Apps depending on Wear can then use `com.google.android.clockwork.*` classes.

**Verification**:

```bash
pm list libraries | grep -i wearable
```

If it lists the library, the jar is loaded.

### 5.9 Battery Stats Cleanup

**What it does**:

```sh
rm -f /data/system/batterystats.bin
rm -f /data/system/battery_stats.bin
```

**Principle**:

Android uses `batterystats.bin` to log battery history and per-app power consumption. Over time the file accumulates stale data, causing battery percentage drift. Deletion makes the system regenerate a clean file.

**Notes**:

- **Doesn't calibrate the battery** (hardware fuel gauge)
- Only cleans software statistics
- Doesn't affect runtime, only display accuracy
- Deleting on every boot is **unnecessary** — only on first boot after flash

### 5.10 Two-Step Animation Fix

**Why two steps**:

```sh
# Step 1: reset
settings put global window_animation_scale 1.0
settings put global transition_animation_scale 1.0
settings put global animator_duration_scale 1.0
sleep 1

# Step 2: tune
settings put global window_animation_scale 0.75
settings put global transition_animation_scale 0.75
settings put global animator_duration_scale 0.5
```

**Principle**:

`SettingsProvider` has an **internal cache**. If some process already read 1.0 at boot, and we directly write 0.75, some components may still use the cached 1.0 until next reboot.

Writing 1.0 first forces a cache flush, then writing the target value ensures all components see the final value.

**Why not 0.5/0.5/0.5**:

- Window 0.75 (faster, not jarring)
- Transition 0.75 (consistent)
- Duration 0.5 (fastest internal interpolation, less "sluggish" feel)

This is the classic animation tuning ratio for Android.

---

## 6. Pitfalls Encountered

Development lessons, documented so you don't repeat them.

### 6.1 APatch Doesn't Execute `update-binary`

**Symptom**: module installs fine, but **nothing** printed via `ui_print` in `update-binary`.

**Cause**: APatch **doesn't read `META-INF/`**. It uses `customize.sh` at module root. `update-binary` is Magisk's legacy path.

**Fix**: create `customize.sh`, put all install output there. Keep `update-binary` as official template for Magisk users.

### 6.2 Don't Redefine `ui_print`

**Symptom**: your own `ui_print()` function, install screen shows nothing.

**Cause**:

```sh
. /data/adb/magisk/util_functions.sh
```

Sourcing this file **auto-defines** `ui_print`. If you redefine after sourcing, you overwrite the official one. The official one writes to `$OUTFD` correctly; yours may not.

**Fix**:

- Define temporary version before sourcing (for env checks)
- After sourcing, **don't touch** `ui_print` — use official

### 6.3 `settings` Command Unreliable in action Context

**Symptom**:

```
cmd: Failure calling service settings: Failed transaction(2147483646)
```

**Cause**: `action.sh` runs in a restricted context, can't bind to the `settings` service.

**Fix**: read XML file instead:

```sh
grep -o "name=\"$1\"[^/]*" /data/system/users/0/settings_global.xml | \
grep -o 'value="[^"]*"' | head -1 | sed 's/value="//;s/"$//'
```

XML is SettingsProvider's persisted file, always readable.

### 6.4 Android toybox Has No awk

**Symptom**:

```
./action.sh[147]: awk: not found
```

**Cause**: Android 8.1's toybox toolbox **removed awk**, only `sed`, `grep`, `cut` remain.

**Fix**:

- Use **BusyBox** bundled with APatch / Magisk (it has awk)
- Or replace floating-point ops with **pure shell integer arithmetic**:

```sh
# Before
awk '{ printf "%.2f V", $1/1000000 }'

# After
volt=$((v / 1000000))
frac=$(((v % 1000000) / 10000))
printf "%d.%02d V" "$volt" "$frac"
```

### 6.5 `stat -c` Unavailable on toybox

**Symptom**: `stat -c '%a'` fails when checking file permissions.

**Cause**: toybox's `stat` is stripped down, no `-c` custom format.

**Fix**: use `ls -l` + `cut`:

```sh
ls -l "$f" | cut -c1-10    # returns "-rw-r--r--"
```

### 6.6 `persist.*` Doesn't Take Effect from build.prop

**Symptom**: changed `persist.sys.5g=false` in `build.prop`, reverts to `true` after reboot.

**Cause**: `persist.*` properties save to `/data/property/persistent_properties` after first boot. System reads this file, not `build.prop` defaults.

**Fix**: use `resetprop -n`:

```sh
resetprop -n persist.sys.5g false
```

`-n` makes `resetprop` **write to the in-memory property area directly**, bypassing property_service, forcing override of stored values.

### 6.7 `ro.*` Needs Two-Layer Insurance

**Symptom**: `ro.*` (read-only) properties apply on change, but some components (SystemUI) still see old values.

**Cause**: `ro.*` properties can't change after set. But **component caches** may still hold old values.

**Fix**: write in two places:

1. `system.prop` (Magisk early injection)
2. `resetprop ro.xxx value` (**without `-n`**, so property_service notices)

### 6.8 Wear Feature False Negative

**Symptom**: Wear files mounted, but `pm list features | grep wearable` returns nothing.

**Cause**: `com.google.android.wearable.xml` declares a **`<library>`** not a `<feature>`. `pm list features` only searches features.

**Fix**: check both:

```sh
pm list libraries | grep -i wearable
```

### 6.9 Timing of Integrity Check

**Question**: when to do file integrity check?

**Answer**: at the **very beginning** of `customize.sh`, before `install_module`.

**Why**:

- Too late — partial files written, rollback difficult
- Too early (in `update-binary`) — APatch doesn't execute it

`customize.sh` is the **only entry point** APatch / Magisk / KernelSU all run.

---

## 7. File Structure

```
SL8541E_Config_Fix/
├── module.prop                          # Module metadata
├── system.prop                          # Property injection (ro.* + persist.* defaults)
├── post-fs-data.sh                      # Early script (persist.* overrides, battery cleanup)
├── service.sh                           # Late script (sysctl, animations, settings)
├── action.sh                            # Action button (status + battery info)
├── customize.sh                         # Install script (integrity, perms, Chinese output)
├── system/                              # Wear OS libraries
│   ├── etc/
│   │   └── permissions/
│   │       └── com.google.android.wearable.xml
│   └── framework/
│       ├── com.google.android.wearable.jar
│       └── wear-service.jar
└── META-INF/
    └── com/google/android/
        ├── update-binary                # Magisk compatibility (APatch ignores)
        └── updater-script               # Placeholder
```

### Script Execution Timing

| Script | When | Purpose |
|---|---|---|
| `customize.sh` | At install | Integrity check, permissions, output |
| `post-fs-data.sh` | Earliest boot (blocking) | `persist.*` override, battery cleanup |
| `service.sh` | After boot (non-blocking) | sysctl, settings, animations |
| `action.sh` | On user button press | Status check, battery info |

---

## 8. Installation

### Prerequisites

- Rooted: **APatch / Magisk v20.4+ / KernelSU**
- Bootloader unlocked
- **Backup your system** (important)

### Steps

1. Package as zip:

```bash
zip -r SL8541E_Config_Fix.zip SL8541E_Config_Fix/
```

2. Push to watch

3. Open root manager → Modules → Install from storage → select zip

4. Reboot

5. Open module card, tap "Action" button to verify

### Notes

- **First install**: install screen shows integrity check + Big Fatty Fish banner
- **Update**: flash new version directly; manager recognizes it as "update"
- **Uninstall**: remove module in manager, reboot

---

## 9. Verification

### 9.1 Property Layer

```bash
su
getprop persist.sys.5g              # false
getprop persist.sys.cpu             # 4
getprop persist.sys.rom.fake        # 0
getprop dalvik.vm.dex2oat-cpu-set   # 0,1,2,3
getprop af.resampler.quality        # 4
```

### 9.2 Kernel Layer

```bash
cat /proc/sys/vm/swappiness                    # 10
cat /sys/block/mmcblk0/queue/scheduler         # noop [noop] or noop [cfq]
cat /proc/sys/net/core/rmem_max                # 8388608
cat /proc/sys/net/ipv4/tcp_congestion_control  # cubic
```

### 9.3 Settings Layer

```bash
settings get global development_settings_enabled   # 1
settings get global window_animation_scale         # 0.75
```

### 9.4 File Layer

```bash
ls -l /system/framework/com.google.android.wearable.jar
ls -l /system/etc/permissions/com.google.android.wearable.xml
pm list libraries | grep -i wearable
```

### 9.5 Quick Way

Tap the module card's "Action" button to see everything at once.

---

## 10. FAQ

### Q1: Why does it show 3GB RAM, not 8GB?

A: **3GB is real. 8GB was fake.** The vendor faked it. If you truly want fake numbers, change `ram.set32g=8GB`.

### Q2: Animation fix says "not effective"?

A: Check whether `service.sh` ran:

```bash
cat /data/adb/modules/SL8541E_Config_Fix/fix.log
```

### Q3: Action button does nothing?

A:
1. Check execution permission: `ls -l /data/adb/modules/SL8541E_Config_Fix/action.sh`
2. Should be `-rwxr-xr-x`
3. If not: `chmod 755`

### Q4: Conflicts with V4A?

A: **No conflict.** This module **completely avoids**:
- `/system/etc/audio_effects.conf`
- `/system/lib/soundfx/`
- `/vendor/lib/soundfx/`
- Any V4A files

Only changed `af.resampler.quality` (AOSP-standard property).

### Q5: Can I raise sample rate to 96k/24bit?

A: **No.** Hardware HAL locked at 44100/16-bit. For hi-res audio, use a **USB DAC**.

### Q6: Can Bluetooth version be upgraded?

A: **No.** Bluetooth version is baked into chip and stack.

### Q7: Was screen density changed?

A: **No.** Even though `system/build.prop` says 194 and `vendor/build.prop` says 320, actual value is whatever `getprop ro.sf.lcd_density` returns at boot. This module **doesn't touch it**.

### Q8: Battery life worse after install?

A: This module **doesn't touch CPU frequency or governor**. Theoretically no impact. If it's worse:
- Another module conflict
- Power-saving disabled makes services more active
- Battery stats cleaned and rebuilding

### Q9: Can I revert to stock?

A: Yes. Remove module + reboot. But **clear `persist.*` overrides**:

```bash
su
resetprop --delete persist.sys.5g
resetprop --delete persist.sys.cpu
# ... or factory reset
```

### Q10: Could this brick my device?

A: This module **only changes properties, settings, sysctl, and injects files** — no partition flashing, no firmware writes. Theoretically safe. But:
- Bad property values could break a function
- Have recovery means (TWRP / factory image)
- **Backup before flashing**

---

## 11. Disclaimer

1. **This module is for study/research purposes only.** Authors are not responsible for device damage, data loss, or warranty voiding.
2. **Flashing has risks.** Understand them before proceeding.
3. **Modifying system properties and settings may void warranty.**
4. **This module contains no cracking, piracy, or verification bypass.** It only performs legitimate system optimization.
5. **Preserve original author credits when redistributing or forking.**

---

## Credits

- **Bilibili Bai Ma Cao** — Project initiator, hardware testing and verification
- **DeepSeek (Big Fatty Fish)** — Code authoring, solution design, pitfall documentation

## License

MIT License
