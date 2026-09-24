# SL8541E Heshuicheng Device Optimization Module

English | [中文](README.md)

Made by [Bili-bamacao](https://space.bilibili.com/1329200878) and DeepSeek ("Big Fatty Fish").

For **Unisoc SL8541E / SC9832E + Heshuicheng (HSC) smartwatches**, Android 8.1.

Compatible with **Magisk / APatch / KernelSU**.

## Background

The stock `build.prop` was full of fake specs:

```properties
ram.set32g=8GB        # actual: 3GB
rom.set32g=128G       # actual: 32GB
persist.sys.5g=true   # no 5G hardware
persist.sys.cpu=10    # 4 cores reported as 10
```

Plus a full telemetry suite (APR / IoT / statistics / heartbeat).

Official fix requires factory reset. This module provides an alternative and disables the telemetry at the same time.

## v1.2 Changes

- **UI real-time priority**: `sys.use_fifo_ui=1` for smoother UI on weak CPUs
- **WebUI**: in-module status page, troubleshooting, about
- **Charging 3A**: corrected the unit issue (µA, not mA)
- **RRO fix** (optional): corrected power_profile.xml for accurate battery stats

## Features

### Fakery Removal

| Item | Original | Current |
|---|---|---|
| 5G icon | true | false |
| CPU display | 10 | 4 |
| RAM display | 8GB | 3GB |
| Storage display | 128G | 32G |

### Telemetry Shutdown

APR suite, heartbeat, BS service, statistics, IoT, UDP collection, sales service registration.

### Biometric Shutdown

Fingerprint (master, app lock, app launch, Soter payment), face unlock.

### Features Enabled

Camera refocus, double-tap recents, lock-screen wallpaper, developer options, eye-care mode, fast charging, hall camera, raise-to-wake.

### Performance & Network

- **dex2oat 4-core fix**: CPU set from wrong `4,5,6,7` to `0,1,2,3`
- TCP buffers, fast open, TIME_WAIT reuse, low-latency
- Congestion algorithm `cubic` (no BBR in this kernel)
- Dynamic DNS guardian for GitHub access

### Audio

- Resampler quality `af.resampler.quality=4`
- **V4A-safe**: does not touch `audio_effects.conf`, `soundfx`, or any V4A files

### Kernel

- I/O scheduler `noop` (kernel has no `deadline`)
- swappiness stays at stock `150`
- Force-disable ZRAM
- Disable system logging (shrink logd buffers)

### Charging

- Input limit raised from 500mA to 3000mA (3A)
- Node unit is **µA**, writes `3000000`
- Must write early at boot (`post-fs-data`), otherwise the node is locked
- **Actual speed depends on charger and cable**

### Animation Fix

- Restore SurfaceFlinger backpressure and vsync sync (`debug.sf.*` back to 0)
- Fix vendor's power-saving-induced frame skipping
- Animation scales 0.75 / 0.75 / 0.5

### WebUI

Round-screen adapted status page with three tabs:

- **Status**: live state of every feature
- **Help**: self-service fixes for 11 common issues
- **About**: module info, credits, links

**Note**: status is a boot-time snapshot. Tap the module card's "Action" button to refresh.

### Environment

- Wear OS libraries (`wearable.jar` + `wear-service.jar` + permission XML)
- GitHub Hosts acceleration (with dynamic guardian)

### Maintenance

- Boot-time battery stats cleanup
- Auto-clear all persist properties on uninstall

## Hardware Limits

| Output Device | Sample Rate | Bit Depth |
|---|---|---|
| Speaker | 44100 | 16bit |
| Wired Headset | 44100 | 16bit |
| BT A2DP | 44100 | 16bit |
| USB DAC | Dynamic | Dynamic |

Sample rate / bit depth / Bluetooth version / signal strength — all hardware-locked. **Only a USB DAC can raise the sample rate.**

## File Structure
