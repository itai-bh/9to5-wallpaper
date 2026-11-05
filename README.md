# 9to5 Wallpaper

A dynamic, time-based wallpaper plugin for **KDE Plasma 6**, providing native macOS-style dynamic desktop capabilities with smooth crossfades, Apple `.heic` container support, an interactive timeline editor, and low-footprint resource management.

---

## Features

- **Smooth Crossfades:** Cinematic GPU-accelerated transitions with configurable duration (e.g. 1500ms with quadratic easing) or instant cuts.
- **Interactive Timeline Editor:**
  - Define exact transition times (`HH:mm`) across 24 hours.
  - Multi-stage presets: *2-Stage (Day/Night)*, *4-Stage (Dawn/Noon/Dusk/Night)*, *8-Stage*, and *16-Stage*.
  - One-click *Distribute Evenly* tool to balance intervals automatically.
- **Staging Shelf & Drag-and-Drop:**
  - Import multiple media files (`JPG`, `PNG`, `WebP`, `AVIF`, `HEIC`) onto a visual staging shelf.
  - Drag images from staging directly onto timeline slots.
- **Apple Dynamic Desktop (`.heic`) Support:**
  - **Import:** Extracts image frames and decodes Apple binary property lists (`bplist00`: `apple_desktop:solar`, `apple_desktop:h24`, and `apple_desktop:apr`).
  - **Desktop Drop:** Drag an Apple dynamic `.heic` file directly onto your desktop to import and activate it.
  - **Export:** Package any configured timeline into a genuine Apple-compatible dynamic `.heic` container via `heif-enc`.
- **Profile Management:**
  - Create, duplicate, and delete profiles stored cleanly as JSON in `~/.local/share/9to5-wallpaper/profiles/`.
- **Resource & Memory Conscious:**
  - **Adaptive Delta Timer:** Computes the exact millisecond delta to the next scheduled transition and sleeps until that moment, eliminating idle CPU polling.
  - **Dual-Buffer Texture Eviction:** Holds exactly one image texture in VRAM during steady state. When crossfading, secondary textures are evicted immediately upon transition completion.
- **Plasma, Lock Screen & Boot Integration:**
  - Native Kirigami settings interface inside KDE's standard wallpaper settings.
  - Dynamic accent color extraction (`accentColor`) synchronized with Plasma.
  - **Lock Screen Sync:** Synchronizes active profile, transitions, and fill mode directly to `kscreenlockerrc`.
  - **Permanent Boot Wallpaper:** 1-click lock action on timeline slot cards to apply or toggle any slot's wallpaper directly to the login manager (Plasma Login Manager / SDDM) via `pkexec`.

---

## Requirements

- **KDE Plasma:** 6.0 or higher
- **Python:** 3.8+ (used by backend helper for metadata parsing)
- **Optional (for HEIC unpack/pack):** `libheif-tools` / `libheif-examples` (provides `heif-enc` and `heif-convert`)

On Fedora:
```bash
sudo dnf install python3 libheif-tools
```
On Ubuntu / Debian:
```bash
sudo apt install python3 libheif-examples
```

On Arch Linux:
```bash
sudo pacman -S python libheif
```

---

## Installation

### Via KDE Store (Recommended)
1. Right-click your desktop and select **Configure Desktop and Wallpaper...**
2. Click **Get New Plugins...**
3. Search for **9to5 Wallpaper** and click **Install**.

### Manual Installation (From Release Archive)
Download `org.kde.plasma.9to5-1.0.0.tar.gz` from Releases and install via `kpackagetool6`:
```bash
kpackagetool6 --type Plasma/Wallpaper -i org.kde.plasma.9to5-1.0.0.tar.gz
```

### From Source
Clone the repository and run the install script:
```bash
git clone https://github.com/<your-username>/9to5-wallpaper.git
cd 9to5-wallpaper
./install.sh
```

---

## Usage

1. Right-click your desktop and choose **Configure Desktop and Wallpaper...**
2. In the **Wallpaper Type** dropdown, select **9to5 Wallpaper**.
3. **Configure Your Timeline:**
   - Click **Add Images** to load pictures into the staging shelf.
   - Drag images from staging into timeline slots, or click **Add Blank Slot**.
   - Set the desired trigger times for each slot.
   - Optionally click **Distribute Evenly** or choose a preset (e.g. 4-Stage).
4. **Tune Display & Transitions:**
   - Toggle transitions on or off and set the crossfade duration (in milliseconds).
   - Configure image fill mode and fallback background color.
5. Click **Apply**.

---

## Changelog

### [v1.1.0]
- **Permanent Boot Wallpaper:** Added a 1-click lock button to timeline slot cards allowing users to apply any slot image directly as the permanent login manager / boot wallpaper (targeting Plasma Login Manager and SDDM via `pkexec`).
- **Lock Screen Synchronization:** Added automatic synchronization of active profiles, transitions, and fill mode directly to KDE's `kscreenlockerrc`.
- **Instant Synchronous Frame Loading:** Implemented synchronous profile pre-loading for the initial desktop and lock screen frame, eliminating black flashes or delay on session startup.

### [v1.0.0]
- Initial release featuring macOS-compatible dynamic HEIC import/export, interactive timeline editor, multi-stage presets, profile manager, and adaptive delta transitions.

---

## AI Ethics
The motivation for this project came from a completely personal standpoint. I just wanted a way to import, use, and make macOS style dynamic wallpapers, and there wasn't a plugin to do so that I was satisfied with. I do not know how to write qml, so I turned to AI. To be upfront, this project is completely vibecoded, i.e. I haven't touched a single line of code. Reading over this, my tone sounds apologetic, but my intention is to disclose. I know people have very valid ethical concerns with the technology, and since I'm not keeping this to myself and publishing it, people should have the right to know. I personally have projects where I'm learning development frameworks purposely without using AI so I can actually learn, but in this case I just want to have some nice looking wallpapers on my laptop.

From a design and implementation standpoint, I've intentionally steered away from anything 'ai slop'. Through iteration I've made sure the UI is dynamic and actually enjoyable to use, and that there aren't gaping holes in functionality. As for performance and resource management, it's fully optimised.

---

## License

This project is licensed under the GNU General Public License v3.0 or later (GPL-3.0-or-later). See [LICENSE](LICENSE) for details.
