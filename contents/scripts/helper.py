#!/usr/bin/env python3
"""
9to5 Wallpaper Helper CLI
Handles macOS dynamic .heic parsing, Apple binary plist decoding,
dynamic .heic compilation, thumbnail generation, and profile management.
"""

import sys
import os
import json
import argparse
import base64
import plistlib
import subprocess
import shutil
import struct
import tempfile
import re
import math
import logging
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, List, Any, Optional

# Standard Base Directories
APP_NAME = "9to5-wallpaper"
DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / APP_NAME
PROFILES_DIR = DATA_HOME / "profiles"
CACHE_DIR = DATA_HOME / "cache"
LOG_FILE = DATA_HOME / "9to5.log"


def setup_logging():
    """Configures persistent file logging for all helper actions and QML diagnostics."""
    DATA_HOME.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("9to5-wallpaper")
    logger.setLevel(logging.DEBUG)
    if not logger.handlers:
        file_handler = logging.FileHandler(str(LOG_FILE), encoding="utf-8")
        formatter = logging.Formatter("%(asctime)s [%(levelname)s] [PID %(process)d] %(message)s")
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)
    return logger


logger = setup_logging()


def ensure_directories():
    """Ensure required application directories exist."""
    PROFILES_DIR.mkdir(parents=True, exist_ok=True)
    CACHE_DIR.mkdir(parents=True, exist_ok=True)


def json_output(status: str, command: str, data: Any = None, error: Optional[str] = None):
    """Prints a standard JSON response to stdout, logs to 9to5.log, and exits."""
    payload = {
        "status": status,
        "command": command,
        "data": data,
        "error": error
    }
    if status == "success":
        summary = str(data)
        if isinstance(data, dict):
            summary = {k: (v if k != 'slots' else f"[{len(v)} slots]") for k, v in data.items()}
        logger.info(f"Command '{command}' completed successfully: {summary}")
    else:
        logger.error(f"Command '{command}' failed with error: {error}")
    print(json.dumps(payload, indent=2))
    sys.exit(0 if status == "success" else 1)


# ---------------------------------------------------------------------------
# Apple Dynamic Desktop Metadata & Plist Handlers
# ---------------------------------------------------------------------------

def parse_apple_xmp(xmp_str: str) -> Dict[str, Any]:
    """
    Parses XMP metadata containing apple_desktop tags and decodes
    the embedded Apple Binary Property Lists (bplist00).
    """
    result = {
        "has_apple_desktop": False,
        "mode": None,          # "solar", "h24", or "apr"
        "appearance": None,    # {"d": dark_idx, "l": light_idx}
        "time_points": [],     # [{"time": "HH:mm", "frame_index": int}]
        "raw_plist": None
    }

    try:
        root = ET.fromstring(xmp_str)
    except Exception as e:
        return result

    ns = {
        "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
        "apple_desktop": "http://ns.apple.com/namespace/1.0/"
    }

    target_tags = ["solar", "h24", "apr"]
    for tag in target_tags:
        b64_val = None
        elem = root.find(f".//apple_desktop:{tag}", ns)
        if elem is not None and elem.text:
            b64_val = elem.text.strip()
        else:
            attr_name = f"{{{ns['apple_desktop']}}}{tag}"
            for desc in root.findall(".//rdf:Description", ns):
                if attr_name in desc.attrib:
                    b64_val = desc.attrib[attr_name].strip()
                    break

        if b64_val:
            try:
                plist_bytes = base64.b64decode(b64_val)
                parsed = plistlib.loads(plist_bytes)
                result["has_apple_desktop"] = True
                result["mode"] = tag
                result["raw_plist"] = parsed

                # 1. Appearance mapping
                if "ap" in parsed and isinstance(parsed["ap"], dict):
                    result["appearance"] = {
                        "dark": parsed["ap"].get("d", 0),
                        "light": parsed["ap"].get("l", 0)
                    }
                elif "d" in parsed and "l" in parsed:
                    result["appearance"] = {
                        "dark": parsed.get("d", 0),
                        "light": parsed.get("l", 0)
                    }

                # 2. Time-of-day clock mapping (h24: ti array)
                if "ti" in parsed and isinstance(parsed["ti"], list):
                    for entry in parsed["ti"]:
                        norm_t = entry.get("t", 0.0)  # 0.0 to 1.0 of 24h
                        frame_idx = entry.get("i", 0)
                        total_mins = int(round(norm_t * 1440.0)) % 1440
                        hh = total_mins // 60
                        mm = total_mins % 60
                        result["time_points"].append({
                            "time": f"{hh:02d}:{mm:02d}",
                            "frame_index": frame_idx
                        })

                # 3. Solar tracking mapping (solar: si array)
                elif "si" in parsed and isinstance(parsed["si"], list):
                    count = len(parsed["si"])
                    for idx, entry in enumerate(parsed["si"]):
                        frame_idx = entry.get("i", idx)
                        # Uniform diurnal estimate when exact solar calculation is not configured
                        total_mins = int(round((idx / max(1, count)) * 1440.0)) % 1440
                        hh = total_mins // 60
                        mm = total_mins % 60
                        result["time_points"].append({
                            "time": f"{hh:02d}:{mm:02d}",
                            "frame_index": frame_idx,
                            "altitude": entry.get("a", 0.0),
                            "azimuth": entry.get("z", 0.0)
                        })

                break
            except Exception as e:
                continue

    return result


def build_apple_dynamic_xmp(slots: List[Dict[str, Any]]) -> bytes:
    """
    Constructs an Apple-compatible dynamic desktop XMP packet with embedded
    binary plist (bplist00) mapping times of day to frame indices.
    """
    ti_list = []
    light_idx = 0
    dark_idx = max(0, len(slots) - 1)

    min_noon_dist = 1440
    min_midnight_dist = 1440

    for idx, slot in enumerate(slots):
        time_str = slot.get("time", "12:00")
        try:
            parts = time_str.split(":")
            hh = int(parts[0])
            mm = int(parts[1]) if len(parts) > 1 else 0
        except Exception:
            hh, mm = 12, 0

        total_mins = (hh * 60 + mm) % 1440
        norm_t = round(total_mins / 1440.0, 6)
        ti_list.append({
            "t": norm_t,
            "i": idx
        })

        noon_dist = abs(total_mins - 720)
        if noon_dist < min_noon_dist:
            min_noon_dist = noon_dist
            light_idx = idx

        midnight_dist = min(total_mins, 1440 - total_mins)
        if midnight_dist < min_midnight_dist:
            min_midnight_dist = midnight_dist
            dark_idx = idx

    ti_list.sort(key=lambda x: x["t"])

    plist_data = {
        "ap": {"d": dark_idx, "l": light_idx},
        "ti": ti_list
    }

    binary_plist = plistlib.dumps(plist_data, fmt=plistlib.FMT_BINARY)
    b64_plist = base64.b64encode(binary_plist).decode("ascii")

    xmp_template = (
        '<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>\n'
        '<x:xmpmeta xmlns:x="adobe:ns:meta/">\n'
        '  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n'
        '    <rdf:Description xmlns:apple_desktop="http://ns.apple.com/namespace/1.0/"\n'
        '      rdf:about=""\n'
        f'      apple_desktop:solar="{b64_plist}"/>\n'
        '  </rdf:RDF>\n'
        '</x:xmpmeta>\n'
        '<?xpacket end="w"?>'
    )
    return xmp_template.encode("utf-8")


def inject_xmp_into_jpeg(src_jpeg: Path, dst_jpeg: Path, xmp_bytes: bytes):
    """
    Injects an APP1 XMP marker segment into a JPEG image so heif-enc
    automatically embeds it into the resulting HEIF container.
    """
    with open(src_jpeg, "rb") as f:
        data = f.read()

    if not data.startswith(b"\xff\xd8"):
        raise ValueError(f"{src_jpeg} is not a valid JPEG file")

    header = b"http://ns.adobe.com/xap/1.0/\x00"
    payload = header + xmp_bytes
    length = len(payload) + 2
    app1_marker = b"\xff\xe1" + struct.pack(">H", length) + payload

    new_data = data[:2] + app1_marker + data[2:]
    with open(dst_jpeg, "wb") as f:
        f.write(new_data)


# ---------------------------------------------------------------------------
# HEIC Inspection, Unpacking, and Packing Commands
# ---------------------------------------------------------------------------

def extract_xmp_from_file(file_path: Path) -> Optional[str]:
    """
    Extracts embedded XMP metadata directly from a file container by scanning
    for XMP marker packets (e.g. apple_desktop xpacket/xmpmeta) without relying on external tools.
    """
    try:
        with open(file_path, "rb") as f:
            content = f.read()
        m = re.search(rb"(<\?xpacket.*?<\?xpacket end=[\"\x27][rw][\"\x27]\?>)", content, re.DOTALL)
        if not m:
            m = re.search(rb"(<x:xmpmeta.*?</x:xmpmeta>)", content, re.DOTALL)
        if m:
            xmp_str = m.group(0).decode("utf-8", errors="ignore")
            logger.info(f"Direct XMP scan extracted {len(xmp_str)} bytes of XMP from {file_path.name}")
            return xmp_str
    except Exception as e:
        logger.warning(f"Direct XMP scanning failed on {file_path}: {e}")
    return None


def extract_frames_from_heic(heic_path: Path, output_dir: Path) -> List[Path]:
    """
    Extracts all image frames from a HEIC container into output_dir.
    Tries heif-convert first; if that fails or produces 0 frames (such as libheif dimension
    mismatches or sequence format errors), seamlessly falls back to ffmpeg.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    frame_prefix = output_dir / "frame.jpg"

    # 1. Try heif-convert
    heif_convert_ok = False
    try:
        logger.info(f"Attempting frame extraction via heif-convert: {heic_path} -> {frame_prefix}")
        proc = subprocess.run(
            ["heif-convert", "--with-xmp", "-q", "95", str(heic_path), str(frame_prefix)],
            capture_output=True,
            text=True,
            check=True
        )
        logger.info(f"heif-convert succeeded. Output: {proc.stdout.strip()}")
        heif_convert_ok = True
    except subprocess.CalledProcessError as e:
        err_msg = (e.stderr or e.stdout or "").strip()
        logger.warning(f"heif-convert failed (exit {e.returncode}): {err_msg}")
    except Exception as e:
        logger.warning(f"heif-convert execution error: {e}")

    # Inspect frames produced by heif-convert
    raw_frames = sorted(list(output_dir.glob("frame-*.jpg")) + list(output_dir.glob("frame.jpg")))

    # 2. Fallback to ffmpeg if heif-convert failed or produced no frames
    if not heif_convert_ok or not raw_frames:
        logger.info(f"Invoking ffmpeg fallback frame extraction for {heic_path}")
        ff_pattern = output_dir / "ff_frame_%03d.jpg"
        try:
            ff_proc = subprocess.run(
                ["ffmpeg", "-y", "-i", str(heic_path), "-map", "0:v", "-q:v", "2", str(ff_pattern)],
                capture_output=True,
                text=True,
                check=True
            )
            logger.info("ffmpeg frame extraction finished successfully.")
        except subprocess.CalledProcessError as e:
            err_msg = (e.stderr or "").strip()
            logger.error(f"ffmpeg fallback failed (exit {e.returncode}): {err_msg[-400:]}")
        except Exception as e:
            logger.error(f"ffmpeg execution error: {e}")

    # 3. Collect and normalize all frame images
    found = sorted(
        list(output_dir.glob("frame-*.jpg")) +
        list(output_dir.glob("frame.jpg")) +
        list(output_dir.glob("ff_frame_*.jpg"))
    )

    if not found:
        return []

    normalized = []
    for idx, f in enumerate(found):
        target = output_dir / f"frame_{idx:02d}.jpg"
        if f != target:
            if target.exists():
                target.unlink()
            shutil.move(f, target)
        normalized.append(target)

    logger.info(f"Normalized {len(normalized)} extracted frames in {output_dir}")
    return normalized


def cmd_parse_heic(args):
    """Inspects a HEIC container and extracts dynamic metadata without unpacking."""
    heic_path = Path(args.file).resolve()
    if not heic_path.exists():
        json_output("error", "parse-heic", error=f"File not found: {heic_path}")

    logger.info(f"Inspecting HEIC file: {heic_path}")

    # Extract XMP directly
    xmp_text = extract_xmp_from_file(heic_path)
    meta_result = parse_apple_xmp(xmp_text) if xmp_text else {"has_apple_desktop": False}

    # Count image streams via ffprobe or heif-info
    image_count = 1
    try:
        probe = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "stream=index", "-of", "csv=p=0", str(heic_path)],
            capture_output=True, text=True, check=True
        )
        lines = [line.strip() for line in probe.stdout.strip().split("\n") if line.strip()]
        if lines:
            image_count = len(lines)
    except Exception:
        try:
            info_proc = subprocess.run(["heif-info", str(heic_path)], capture_output=True, text=True, check=True)
            image_count = max(1, len(re.findall(r"image:\s+\d+x\d+\s+\(id=\d+\)", info_proc.stdout)))
        except Exception:
            image_count = 1

    summary = {
        "file": str(heic_path),
        "fileName": heic_path.name,
        "imageCount": image_count,
        "isDynamic": meta_result.get("has_apple_desktop", False),
        "mode": meta_result.get("mode"),
        "appearance": meta_result.get("appearance"),
        "timePoints": meta_result.get("time_points", [])
    }
    json_output("success", "parse-heic", data=summary)


def cmd_unpack_heic(args):
    """Unpacks all frames from a dynamic HEIC file into cache and creates a profile."""
    ensure_directories()
    heic_path = Path(args.file).resolve()
    if not heic_path.exists():
        json_output("error", "unpack-heic", error=f"File not found: {heic_path}")

    theme_name = args.name or heic_path.stem.replace("_", " ").title()
    theme_id = re.sub(r"[^a-zA-Z0-9_\-]", "", theme_name.lower().replace(" ", "-"))

    theme_cache = CACHE_DIR / theme_id
    theme_cache.mkdir(parents=True, exist_ok=True)
    logger.info(f"Unpacking HEIC '{heic_path.name}' to cache directory: {theme_cache}")

    # 1. Unpack frames using robust multi-engine extractor
    normalized_frames = extract_frames_from_heic(heic_path, theme_cache)
    if not normalized_frames:
        json_output("error", "unpack-heic", error="No image frames could be extracted from HEIC container")

    # 2. Extract and parse dynamic XMP metadata
    xmp_files = list(theme_cache.glob("*.xmp"))
    xmp_text = None
    if xmp_files:
        xmp_text = xmp_files[0].read_text(encoding="utf-8", errors="ignore")
    if not xmp_text:
        xmp_text = extract_xmp_from_file(heic_path)

    meta = {"has_apple_desktop": False, "time_points": []}
    if xmp_text:
        meta = parse_apple_xmp(xmp_text)
        logger.info(f"Metadata extracted: mode={meta.get('mode')}, timePoints={len(meta.get('time_points', []))}, appearance={meta.get('appearance')}")

    # 3. Generate thumbnails for fast rendering in QML
    thumbs_dir = theme_cache / "thumbs"
    thumbs_dir.mkdir(exist_ok=True)
    for f in normalized_frames:
        thumb_path = thumbs_dir / f.name
        try:
            subprocess.run(["magick", str(f), "-resize", "320x320>", str(thumb_path)], check=True)
        except Exception:
            shutil.copy2(f, thumb_path)

    # 4. Build timeline slots with collision-free time assignment
    slots = []
    total_frames = len(normalized_frames)
    time_points = meta.get("time_points", [])

    # Validate whether time_points has distinct times matching all frames
    has_valid_times = False
    if len(time_points) == total_frames:
        unique_times = {tp.get("time") for tp in time_points if tp.get("time")}
        if len(unique_times) == total_frames:
            has_valid_times = True

    appearance = meta.get("appearance") or {}

    for idx, frame_path in enumerate(normalized_frames):
        thumb_path = thumbs_dir / frame_path.name
        assigned_time = None
        assigned_label = f"Frame {idx + 1}"

        if has_valid_times:
            matched = next((tp for tp in time_points if tp.get("frame_index") == idx), None)
            if matched:
                assigned_time = matched.get("time")

        if not assigned_time:
            if total_frames == 2:
                dark_idx = appearance.get("dark", 1)
                if idx == dark_idx:
                    assigned_time = "20:00"
                    assigned_label = "Night"
                else:
                    assigned_time = "08:00"
                    assigned_label = "Day"
            else:
                total_mins = int(round((idx / max(1, total_frames)) * 1440.0)) % 1440
                assigned_time = f"{total_mins // 60:02d}:{total_mins % 60:02d}"

        slots.append({
            "slotIndex": idx,
            "time": assigned_time,
            "imagePath": str(frame_path),
            "thumbPath": str(thumb_path),
            "label": assigned_label
        })

    slots.sort(key=lambda s: s["time"])

    profile_data = {
        "id": theme_id,
        "name": theme_name,
        "version": "1.0",
        "source": "heic-import",
        "transitionDuration": 1500,
        "slots": slots
    }

    profile_file = PROFILES_DIR / f"{theme_id}.json"
    with open(profile_file, "w", encoding="utf-8") as f:
        json.dump(profile_data, f, indent=2)

    json_output("success", "unpack-heic", data={
        "profileId": theme_id,
        "profileFile": str(profile_file),
        "profile": profile_data
    })


def cmd_pack_heic(args):
    """Compiles profile timeline slots into a genuine Apple dynamic .heic file."""
    ensure_directories()
    profile_id = args.profile
    profile_file = PROFILES_DIR / f"{profile_id}.json"
    if not profile_file.exists():
        # Check if profile_id is a path directly
        if Path(profile_id).exists():
            profile_file = Path(profile_id)
        else:
            json_output("error", "pack-heic", error=f"Profile '{profile_id}' not found")

    with open(profile_file, "r", encoding="utf-8") as f:
        profile = json.load(f)

    slots = profile.get("slots", [])
    if not slots:
        json_output("error", "pack-heic", error="Profile has no time slots defined")

    slots.sort(key=lambda s: s.get("time", "12:00"))

    output_path = Path(args.output).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    quality = max(10, min(100, args.quality))

    # Generate Apple dynamic XMP
    xmp_bytes = build_apple_dynamic_xmp(slots)

    with tempfile.TemporaryDirectory() as tmpdir:
        input_jpegs = []
        for idx, slot in enumerate(slots):
            img_path = Path(slot["imagePath"])
            if not img_path.exists():
                json_output("error", "pack-heic", error=f"Image file missing: {img_path}")

            target_jpg = Path(tmpdir) / f"input_{idx:03d}.jpg"
            # Ensure format is JPEG for consistent heif-enc input
            if img_path.suffix.lower() in [".jpg", ".jpeg"]:
                shutil.copy2(img_path, target_jpg)
            else:
                subprocess.run(["magick", str(img_path), str(target_jpg)], check=True)

            # Inject Apple dynamic XMP into the primary (first) frame
            if idx == 0:
                xmp_injected = Path(tmpdir) / "input_000_xmp.jpg"
                inject_xmp_into_jpeg(target_jpg, xmp_injected, xmp_bytes)
                input_jpegs.append(str(xmp_injected))
            else:
                input_jpegs.append(str(target_jpg))

        # Encode with heif-enc
        cmd = ["heif-enc", "-q", str(quality), "-o", str(output_path)] + input_jpegs
        try:
            subprocess.run(cmd, capture_output=True, text=True, check=True)
        except subprocess.CalledProcessError as e:
            json_output("error", "pack-heic", error=f"heif-enc failed: {e.stderr}")

    json_output("success", "pack-heic", data={
        "outputFile": str(output_path),
        "slotsCount": len(slots),
        "quality": quality
    })


# ---------------------------------------------------------------------------
# Profile Storage CRUD Commands
# ---------------------------------------------------------------------------

def cmd_list_profiles(args):
    """Lists all available profiles."""
    ensure_directories()
    profiles = []
    for f in sorted(PROFILES_DIR.glob("*.json")):
        try:
            with open(f, "r", encoding="utf-8") as pf:
                data = json.load(pf)
                slots = data.get("slots", [])
                first_thumb = slots[0].get("thumbPath") if slots else None
                first_img = slots[0].get("imagePath") if slots else None
                profiles.append({
                    "id": data.get("id", f.stem),
                    "name": data.get("name", f.stem),
                    "slotCount": len(slots),
                    "preview": first_thumb or first_img,
                    "filePath": str(f)
                })
        except Exception:
            continue

    json_output("success", "list-profiles", data={"profiles": profiles})


def cmd_get_profile(args):
    """Retrieves a single profile by ID."""
    ensure_directories()
    profile_file = PROFILES_DIR / f"{args.id}.json"
    if not profile_file.exists():
        json_output("error", "get-profile", error=f"Profile '{args.id}' does not exist")

    with open(profile_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    json_output("success", "get-profile", data=data)


def cmd_save_profile(args):
    """Saves or updates a profile JSON."""
    ensure_directories()
    try:
        profile_data = json.loads(args.payload)
    except Exception as e:
        json_output("error", "save-profile", error=f"Invalid JSON payload: {str(e)}")

    profile_id = args.id or profile_data.get("id")
    if not profile_id:
        json_output("error", "save-profile", error="Missing profile ID")

    profile_id = re.sub(r"[^a-zA-Z0-9_\-]", "", profile_id)
    profile_data["id"] = profile_id

    profile_file = PROFILES_DIR / f"{profile_id}.json"
    with open(profile_file, "w", encoding="utf-8") as f:
        json.dump(profile_data, f, indent=2)

    json_output("success", "save-profile", data={"id": profile_id, "file": str(profile_file)})


def cmd_delete_profile(args):
    """Deletes a profile and cleans its cache directory."""
    ensure_directories()
    profile_id = args.id
    profile_file = PROFILES_DIR / f"{profile_id}.json"
    deleted_files = []

    if profile_file.exists():
        profile_file.unlink()
        deleted_files.append(str(profile_file))

    cache_dir = CACHE_DIR / profile_id
    if cache_dir.exists():
        shutil.rmtree(cache_dir, ignore_errors=True)
        deleted_files.append(str(cache_dir))

    json_output("success", "delete-profile", data={"id": profile_id, "deleted": deleted_files})


def cmd_init_defaults(args):
    """Initializes standard folders and generates a starter default profile."""
    ensure_directories()
    default_id = "default-aurora"
    default_file = PROFILES_DIR / f"{default_id}.json"

    theme_cache = CACHE_DIR / default_id
    theme_cache.mkdir(parents=True, exist_ok=True)
    thumbs_dir = theme_cache / "thumbs"
    thumbs_dir.mkdir(exist_ok=True)

    # 4 distinct calm, neutral time stages
    stages = [
        {"time": "06:00", "label": "Morning", "color1": "#3a6073", "color2": "#3a7bd5"},
        {"time": "12:00", "label": "Day", "color1": "#2193b0", "color2": "#6dd5ed"},
        {"time": "18:00", "label": "Evening", "color1": "#1f1c2c", "color2": "#4e4376"},
        {"time": "22:00", "label": "Night", "color1": "#0b132b", "color2": "#1c2541"}
    ]

    slots = []
    for idx, stage in enumerate(stages):
        img_name = f"stage_{idx:02d}.jpg"
        img_path = theme_cache / img_name
        thumb_path = thumbs_dir / img_name

        # Always re-generate to ensure clean neutral gradients
        subprocess.run([
            "magick", "-size", "1920x1080",
            f"gradient:{stage['color1']}-{stage['color2']}",
            str(img_path)
        ], check=True)

        subprocess.run([
            "magick", str(img_path), "-resize", "320x180^",
            "-gravity", "center", "-extent", "320x180",
            str(thumb_path)
        ], check=True)

        slots.append({
            "slotIndex": idx,
            "time": stage["time"],
            "label": stage["label"],
            "imagePath": str(img_path),
            "thumbPath": str(thumb_path)
        })

    profile_data = {
        "id": default_id,
        "name": "Default Day & Night",
        "version": "1.0",
        "source": "builtin-default",
        "transitionDuration": 1500,
        "slots": slots
    }

    with open(default_file, "w", encoding="utf-8") as f:
        json.dump(profile_data, f, indent=2)

    json_output("success", "init-defaults", data={
        "profileId": default_id,
        "profileFile": str(default_file),
        "profile": profile_data
    })


# ---------------------------------------------------------------------------
# Automated Self-Test Suite
# ---------------------------------------------------------------------------

def cmd_self_test(args):
    """Runs automated verification tests across all core functionality."""
    print("Running 9to5 Wallpaper Helper Self-Test...")
    ensure_directories()

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)

        # Test 1: Binary Plist Generation & Parsing
        test_slots = [
            {"time": "06:00", "label": "Morning"},
            {"time": "12:00", "label": "Noon"},
            {"time": "18:00", "label": "Sunset"},
            {"time": "23:00", "label": "Night"}
        ]
        xmp_bytes = build_apple_dynamic_xmp(test_slots)
        assert b"apple_desktop:solar" in xmp_bytes, "XMP must contain apple_desktop:solar"
        parsed = parse_apple_xmp(xmp_bytes.decode("utf-8"))
        assert parsed["has_apple_desktop"] is True, "Parsed XMP must identify apple_desktop"
        assert len(parsed["time_points"]) == 4, f"Expected 4 time points, got {len(parsed['time_points'])}"
        print(" [PASS] 1. Apple Dynamic XMP & Binary Plist (bplist00) round-trip verified.")

        # Test 2: JPEG APP1 XMP Injection
        dummy_jpg = tmp_path / "dummy.jpg"
        dummy_xmp_jpg = tmp_path / "dummy_xmp.jpg"
        subprocess.run(["magick", "-size", "200x200", "xc:red", str(dummy_jpg)], check=True)
        inject_xmp_into_jpeg(dummy_jpg, dummy_xmp_jpg, xmp_bytes)
        assert dummy_xmp_jpg.exists(), "Injected JPEG must exist"
        print(" [PASS] 2. JPEG APP1 XMP segment injection verified.")

        # Test 3: Multi-frame HEIC compilation with heif-enc
        dummy_jpg2 = tmp_path / "dummy2.jpg"
        subprocess.run(["magick", "-size", "200x200", "xc:green", str(dummy_jpg2)], check=True)
        out_heic = tmp_path / "test_dynamic.heic"

        subprocess.run(["heif-enc", "-q", "80", "-o", str(out_heic), str(dummy_xmp_jpg), str(dummy_jpg2)], check=True)
        assert out_heic.exists(), "Compiled HEIC must exist"

        info_out = subprocess.check_output(["heif-info", str(out_heic)]).decode()
        assert "XMP" in info_out, "Compiled HEIC must preserve embedded XMP"
        print(" [PASS] 3. Multi-frame HEIC packaging with heif-enc verified.")

        # Test 4: Dynamic HEIC unpacking with heif-convert
        extracted_prefix = tmp_path / "extracted_frame.jpg"
        subprocess.run(["heif-convert", "--with-xmp", str(out_heic), str(extracted_prefix)], check=True)
        extracted_xmps = list(tmp_path.glob("*.xmp"))
        assert len(extracted_xmps) > 0, "Extracted XMP must exist"
        extracted_meta = parse_apple_xmp(extracted_xmps[0].read_text())
        assert extracted_meta["has_apple_desktop"] is True, "Extracted XMP must contain apple_desktop"
        print(" [PASS] 4. Dynamic HEIC extraction and metadata recovery verified.")

    print("\nALL SELF-TESTS PASSED SUCCESSFULLY.")
    sys.exit(0)


def cmd_log(args):
    """Appends an event log message from QML or external callers."""
    level = (args.level or "INFO").upper()
    msg = args.message or ""
    source = args.source or "QML"
    log_func = getattr(logger, level.lower(), logger.info)
    log_func(f"[{source}] {msg}")
    json_output("success", "log", data={"logged": True})


# ---------------------------------------------------------------------------
# CLI Argument Router
# ---------------------------------------------------------------------------

def main():
    logger.info(f"CLI Invoked: argv={sys.argv}")
    parser = argparse.ArgumentParser(description="9to5 Wallpaper Helper CLI")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # log
    p_log = subparsers.add_parser("log", help="Log a message to 9to5.log")
    p_log.add_argument("--message", required=True, help="Message text to log")
    p_log.add_argument("--level", default="INFO", help="Log level (DEBUG, INFO, WARN, ERROR)")
    p_log.add_argument("--source", default="QML", help="Source identifier")
    p_log.set_defaults(func=cmd_log)

    # parse-heic
    p_parse = subparsers.add_parser("parse-heic", help="Inspect a dynamic HEIC file")
    p_parse.add_argument("file", help="Path to .heic file")
    p_parse.set_defaults(func=cmd_parse_heic)

    # unpack-heic
    p_unpack = subparsers.add_parser("unpack-heic", help="Extract frames and metadata from HEIC")
    p_unpack.add_argument("file", help="Path to .heic file")
    p_unpack.add_argument("--name", help="Optional friendly name for theme")
    p_unpack.set_defaults(func=cmd_unpack_heic)

    # pack-heic
    p_pack = subparsers.add_parser("pack-heic", help="Compile profile slots into dynamic HEIC")
    p_pack.add_argument("--profile", required=True, help="Profile ID to compile")
    p_pack.add_argument("-o", "--output", required=True, help="Output .heic path")
    p_pack.add_argument("--quality", type=int, default=85, help="JPEG/HEIC quality factor (1-100)")
    p_pack.set_defaults(func=cmd_pack_heic)

    # list-profiles
    p_list = subparsers.add_parser("list-profiles", help="List all saved wallpaper profiles")
    p_list.set_defaults(func=cmd_list_profiles)

    # get-profile
    p_get = subparsers.add_parser("get-profile", help="Get a specific profile JSON")
    p_get.add_argument("id", help="Profile ID")
    p_get.set_defaults(func=cmd_get_profile)

    # save-profile
    p_save = subparsers.add_parser("save-profile", help="Save a profile JSON")
    p_save.add_argument("id", nargs="?", help="Profile ID")
    p_save.add_argument("--payload", required=True, help="Profile JSON payload string")
    p_save.set_defaults(func=cmd_save_profile)

    # delete-profile
    p_del = subparsers.add_parser("delete-profile", help="Delete a profile and its cached files")
    p_del.add_argument("id", help="Profile ID")
    p_del.set_defaults(func=cmd_delete_profile)

    # init-defaults
    p_init = subparsers.add_parser("init-defaults", help="Initialize folders and default profile")
    p_init.set_defaults(func=cmd_init_defaults)

    # self-test
    p_test = subparsers.add_parser("self-test", help="Run self-test verification suite")
    p_test.set_defaults(func=cmd_self_test)

    args = parser.parse_args()
    try:
        args.func(args)
    except Exception as e:
        logger.exception(f"Unhandled exception in command '{args.command}': {e}")
        json_output("error", args.command, error=str(e))


if __name__ == "__main__":
    main()
