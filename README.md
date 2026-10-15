<p align="center">
  <img src="docs/images/icon.png" width="128" alt="PowerDeck app icon">
</p>

<h1 align="center">PowerDeck</h1>

<p align="center">
  <b>See where your Mac's power goes, live.</b><br>
  Your charger, battery and everything you plug in, in one simple dashboard.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white" alt="macOS 15 or later">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-MIT-34D399" alt="MIT license">
</p>

<p align="center">
  <img src="docs/images/overview.png" alt="PowerDeck's Overview: battery status, an animated power-flow diagram from a 30 W charger to the Mac, its battery and a connected iPhone, live stats and advice" width="100%">
</p>

## What it does

- **Live power flow:** watch power move from your charger into your Mac, its battery and your devices.
- **Plugged-in devices:** see what's in each port, how fast it's charging and how fast it can transfer data.
- **Charger check:** find out if your charger is strong enough for your Mac.
- **Battery health:** charge, health and cycle count at a glance.
- **Simple advice:** tips in plain English, like when your phone is draining your Mac's battery.
- **Menu bar and alerts:** live wattage in the menu bar, and a heads-up when you plug something in.

## Screenshots

<table>
  <tr>
    <td width="50%"><img src="docs/images/devices.png" alt="Devices: three ports and a connected iPhone with its speed and power draw"></td>
    <td width="50%"><img src="docs/images/power.png" alt="Power: battery health, charger details and a live power chart"></td>
  </tr>
  <tr>
    <td align="center"><b>Devices</b></td>
    <td align="center"><b>Power</b></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/images/system.png" alt="System: CPU, memory, busiest apps and temperature"></td>
    <td width="50%" align="center">
      <img src="docs/images/menubar.png" alt="Menu bar panel" width="70%"><br><br>
      <img src="docs/images/alert.png" alt="Alert: iPhone connected" width="85%">
    </td>
  </tr>
  <tr>
    <td align="center"><b>System</b></td>
    <td align="center"><b>Menu bar and alerts</b></td>
  </tr>
</table>

## Install

You need macOS 15 or later and Xcode (or just run `xcode-select --install`).

```bash
git clone https://github.com/avi20009/PowerDeck.git
cd PowerDeck
scripts/build.sh --open
```

PowerDeck opens when the build finishes. To keep it, drag `build/PowerDeck.app` into your **Applications** folder.

## How to use

- Switch between **Overview**, **Devices**, **Power** and **System** with the tabs at the top (or ⌘1 to ⌘4).
- Click **⚡** in the menu bar for a quick look.
- Hover the **?** on any card to see what it means.
- Press **⌘,** for Settings: menu bar display, refresh rate and alerts.

Works best on MacBooks with Apple silicon (M1 or later).

---

<p align="center">
  Made by <b>Avi Barvaliya</b> (<a href="https://github.com/avi20009">@avi20009</a>) · <a href="LICENSE">MIT license</a> · <a href="docs/how-it-works.md">How it works</a>
</p>
