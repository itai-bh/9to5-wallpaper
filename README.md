# 9to5 Wallpaper (`9to5-wallpaper`)

A dynamic, time-based wallpaper extension for **KDE Plasma 6**, providing native dynamic desktop capabilities similar to macOS Dynamic Desktop with full support for Apple `.heic` containers, interactive timeline scheduling, and zero-leak memory management.

---

## Project Structure

```text
9to5-wallpaper/
├── metadata.json              # KDE Plasma 6 KPackage plugin manifest
├── contents/
│   ├── config/
│   │   └── main.xml           # KConfigXT schema declaring persistent configuration entries
│   ├── scripts/
│   │   └── helper.py          # Python 3 CLI for HEIC compilation, XMP decoding & profiles
│   └── ui/
│       ├── main.qml           # Desktop wallpaper runtime (dual-buffered crossfader & delta scheduler)
│       ├── config.qml         # Native KDE Settings UI (Kirigami.FormLayout)
│       ├── SlotCard.qml       # Time slot card with DropArea and thumbnail preview
│       └── StagingCard.qml    # Draggable thumbnail component for staged media
├── CMakeLists.txt             # CMake build & system installation specification
├── install.sh                 # Quick development symlink installer
├── uninstall.sh               # Cleanup script
├── .gitignore
└── README.md
```

---

## Key Features

1. **Preset & Custom Timeline Scheduling:**
   - Define custom times of day (`HH:mm`) or choose presets: *2-Stage (Day/Night)*, *4-Stage (Dawn/Noon/Dusk/Night)*, *8-Stage*, or *16-Stage*.
   - Auto-distribute evenly across 24 hours with one click.
2. **Bulk Image Import & Drag-and-Drop:**
   - Import multiple images (`JPG`, `PNG`, `WebP`, `AVIF`, `HEIC`) into a temporary staging shelf.
   - Drag images from the staging shelf and drop them directly onto any timeline slot.
3. **Apple Dynamic `.heic` Support:**
   - **Import:** Extracts frames and decodes Apple binary property lists (`bplist00`: `apple_desktop:solar`, `apple_desktop:h24`, `apple_desktop:apr`).
   - **Export:** Packages configured timeline slots into genuine Apple-compatible dynamic `.heic` files using `heif-enc` and standard XMP metadata.
4. **Profile Management:**
   - Create, duplicate, and delete dynamic wallpaper profiles.
   - Stored cleanly as JSON in `~/.local/share/9to5-wallpaper/profiles/`.
5. **Memory & Performance Conscious (`plasmashell` Safe):**
   - **Dual-buffered rendering:** Keeps exactly 1 texture in memory during normal operation, and 2 during crossfades. Unused textures are evicted immediately.
   - **Adaptive delta timer:** Sleeps until the exact millisecond of the next transition instead of waking the CPU every second, with a relaxed 60s heartbeat guard for system clock jumps or sleep/wake events.

---

## Development & Testing

### 1. Local Development (Symlink Mode)
Run once to link this repository into your user wallpaper directory:
```bash
./install.sh
```

### 2. Live Testing
* **Test the Settings UI:** Right-click desktop → **Configure Desktop and Wallpaper...** → Select **9to5 Wallpaper**. (Closing and re-opening this dialog reloads `config.qml` from disk immediately).
* **Test the Runtime:** Reload plasmashell without logging out:
  ```bash
  systemctl --user restart plasma-plasmashell
  ```
* **View Live Logs:**
  ```bash
  journalctl --user -u plasma-plasmashell -f
  ```
* **Run Helper Self-Tests:**
  ```bash
  python3 contents/scripts/helper.py self-test
  ```
* **Lint QML:**
  ```bash
  qmllint contents/ui/*.qml
  ```
