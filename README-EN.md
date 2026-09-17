# SL8541E Heshuicheng Device Optimization Module

English | [中文](README.md)

Made by [Bili-bamacao](https://space.bilibili.com/1329200878) and DeepSeek ("Big Fatty Fish").

For **Unisoc SL8541E / SC9832E + Heshuicheng (HSC) smartwatches**, Android 8.1.

Compatible with **Magisk / APatch / KernelSU**.

## Background

The stock `build.prop` contains fake specs:

```properties
ram.set32g=8GB        # actual: 3GB
rom.set32g=128G       # actual: 32GB
persist.sys.5g=true   # no 5G hardware
persist.sys.cpu=10    # 4 cores reported as 10
```

Also includes APR, IoT, and telemetry reporting.

Official fix requires factory reset. This module provides an alternative and disables telemetry.

Features

Fakery Removal

Item Original Current
5G icon true false
CPU display 10 4
RAM display 8GB 3GB
Storage display 128G 32G

Telemetry Shutdown

APR, heartbeat, BS service, statistics, IoT, UDP data collection, sales service registration.

Biometric Shutdown

Fingerprint (master, app lock, app launch, Soter payment), face unlock.

Features Enabled

Camera refocus, double-tap recents, lock-screen wallpaper, developer options, eye-care mode, fast charging, hall camera, raise-to-wake.

Performance & Network

· dex2oat 4-core fix (CPU set 4,5,6,7 → 0,1,2,3)
· TCP buffer, fast open, TIME_WAIT reuse, low-latency
· Congestion algorithm stays cubic (no BBR in this kernel)

Audio

· Resampler quality af.resampler.quality=4
· V4A-safe: does not touch audio_effects.conf, soundfx, or any V4A files

Kernel

· I/O scheduler noop (this kernel has no deadline)
· swappiness stays at stock 150

Environment

· Wear OS libraries (wearable.jar + wear-service.jar + permission XML)
· GitHub Hosts acceleration

Maintenance

· Boot-time battery stats cleanup
· Two-step animation fix (window 0.75 / transition 0.75 / duration 0.5)

Hardware Limits

Output Device Sample Rate Bit Depth
Speaker 44100 16bit
Wired Headset 44100 16bit
BT A2DP 44100 16bit
USB DAC Dynamic Dynamic

Sample rate/bit depth are hardware-locked. Only a USB DAC can raise them. Same for Bluetooth version and signal strength.

File Structure

```
SL8541E_Config_Fix/
├── module.prop
├── system.prop
├── post-fs-data.sh
├── service.sh
├── action.sh
├── customize.sh
├── system/
│   ├── etc/
│   │   ├── hosts
│   │   └── permissions/com.google.android.wearable.xml
│   └── framework/
│       ├── com.google.android.wearable.jar
│       └── wear-service.jar
└── META-INF/com/google/android/
    ├── update-binary
    └── updater-script
```

Installation

1. Download SL8541E_Config_Fix_v1.0.zip
2. Root manager → Modules → Install from storage
3. Reboot
4. Tap "Action" on the module card to verify

Prerequisites: Rooted, Bootloader unlocked, system backed up.

Verification

```bash
su

# Property layer
getprop persist.sys.5g              # false
getprop persist.sys.cpu             # 4
getprop dalvik.vm.dex2oat-cpu-set   # 0,1,2,3
getprop af.resampler.quality        # 4

# Kernel layer
cat /proc/sys/vm/swappiness         # 150
cat /sys/block/mmcblk0/queue/scheduler  # 【noop】
cat /proc/sys/net/core/rmem_max     # 8388608

# Settings layer
settings get global window_animation_scale  # 0.75
```

Or tap "Action" for a full readout.

FAQ

Q: Is 3GB RAM real?
A: Yes. 8GB was faked.

Q: Conflicts with V4A?
A: No. Module doesn't touch V4A files.

Q: Can I get 96k/24bit audio?
A: No. Hardware locked at 44100/16bit. USB DAC only.

Q: Battery life worse?
A: Module doesn't touch CPU frequency or governor.

Q: Can it brick the device?
A: Only changes properties, settings, sysctl, and injects files. Still, back up first.

Q: How to revert?
A: Remove module + reboot. To clear persist overrides: resetprop --delete persist.sys.5g etc.

Compatibility

Item Notes
Works on SL8541E / SC9832E + Heshuicheng
Not for Other vendors
Doesn't touch Screen density, Bluetooth version, signal strength
Skipped zram (not needed in practice)

Feedback

Issues should include: full Action output, fix.log, device model and OS version, reproduction steps.

Credits

· Bili-bamacao — Project initiator, hardware testing
· DeepSeek ("Big Fatty Fish") — Code authoring, solution design

License

MIT License

---

🐟 Big Fatty Fish
The watch's ceiling is mapped. Everything that can be done, is done.

```
