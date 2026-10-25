#!/usr/bin/env python3
"""Download and turn YouTube captions into a readable transcript.

This program deliberately uses the bundled yt-dlp.exe instead of scraping a
YouTube web page.  It supports creator captions as well as auto-generated
captions, and has no Python package dependencies.
"""

from __future__ import annotations

import argparse
import html
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

DEFAULT_LANGUAGES = "vi.*,en.*,.*-orig"


def bundled_ytdlp() -> Path:
    """Find yt-dlp beside the frozen executable or this source file."""
    exe_dir = Path(sys.executable).parent
    root = Path(getattr(sys, "_MEIPASS", exe_dir))
    source_dir = Path(__file__).resolve().parent
    candidates = (
        exe_dir / "yt-dlp.exe",
        exe_dir / "lib" / "yt-dlp.exe",
        root / "yt-dlp.exe",
        root / "lib" / "yt-dlp.exe",
        source_dir / "yt-dlp.exe",
        source_dir / "lib" / "yt-dlp.exe",
    )
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    found = shutil.which("yt-dlp")
    if found:
        return Path(found)
    raise FileNotFoundError("lib\\yt-dlp.exe was not found.")


def timestamp(seconds: float) -> str:
    seconds = max(0, int(seconds))
    return f"[{seconds // 3600:02}:{(seconds // 60) % 60:02}:{seconds % 60:02}]"


def vtt_to_transcript(vtt_file: Path) -> str:
    """Remove WebVTT markup and the repeated lines of rolling captions."""
    lines = vtt_file.read_text(encoding="utf-8-sig", errors="replace").splitlines()
    result: list[str] = []
    previous_lines: list[str] = []
    for index, line in enumerate(lines):
        if "-->" not in line:
            continue
        start = line.split("-->", 1)[0].strip().replace(",", ".")
        match = re.match(r"(?:(\d+):)?(\d{2}):(\d{2}(?:\.\d+)?)", start)
        if not match:
            continue
        hours, minutes, secs = match.groups(default="0")
        when = int(hours) * 3600 + int(minutes) * 60 + float(secs)
        cue_lines: list[str] = []
        for cue_line in lines[index + 1:]:
            if not cue_line.strip() or "-->" in cue_line:
                break
            clean = re.sub(r"<[^>]+>", "", cue_line)
            clean = re.sub(r"\s+", " ", html.unescape(clean)).strip()
            if clean:
                cue_lines.append(clean)
        if not cue_lines:
            continue
        # Auto-generated captions are "rolling": each cue repeats the line(s)
        # of the previous cue, so keep only the lines that are new.
        new_lines = [item for item in cue_lines if item not in previous_lines]
        previous_lines = cue_lines
        text = " ".join(new_lines).strip()
        if text:
            result.append(f"{timestamp(when)} {text}")
    return "\n".join(result)


def caption_language(path: Path) -> str:
    """'subtitle.vi.vtt' -> 'vi'."""
    stem = path.name[:-4] if path.name.lower().endswith(".vtt") else path.name
    return stem.split(".", 1)[1] if "." in stem else ""


def pick_caption(captions: list[Path], languages: str) -> Path:
    """Choose the caption file following the language priority order."""
    for pattern in (p.strip() for p in languages.split(",")):
        if not pattern or pattern.lower() == "all":
            continue
        try:
            regex = re.compile(pattern, re.IGNORECASE)
        except re.error:
            continue
        for caption in captions:
            if regex.fullmatch(caption_language(caption)):
                return caption
    return captions[0]


def get_transcript(url: str, languages: str) -> str:
    ytdlp = bundled_ytdlp()
    with tempfile.TemporaryDirectory(prefix="vdh-transcript-") as temp:
        target = Path(temp) / "subtitle.%(ext)s"
        command = [
            str(ytdlp), "--ignore-config", "--skip-download", "--no-playlist",
            "--no-warnings", "--write-subs", "--write-auto-subs",
            "--sub-langs", languages, "--sub-format", "vtt",
            "-o", str(target), "--", url,
        ]
        extra = {}
        if sys.platform == "win32":
            extra["creationflags"] = subprocess.CREATE_NO_WINDOW  # no console flash
        try:
            completed = subprocess.run(
                command, capture_output=True, text=True, encoding="utf-8",
                errors="replace", timeout=180, **extra,
            )
        except subprocess.TimeoutExpired:
            raise RuntimeError("yt-dlp took too long to respond (timeout).")
        captions = sorted(Path(temp).glob("*.vtt"))
        if not captions:
            detail = (completed.stderr or completed.stdout or "").strip()
            if completed.returncode:
                raise RuntimeError(detail or "yt-dlp cannot load subtitles.")
            raise RuntimeError("This video has no subtitles or the auto-subtitles are not suitable.")
        transcript = vtt_to_transcript(pick_caption(captions, languages))
        if not transcript:
            raise RuntimeError("The subtitles were downloaded but their content could not be read.")
        return transcript


def main() -> int:
    # Keep Vietnamese/Unicode error messages from crashing on legacy consoles.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    parser = argparse.ArgumentParser(description="Get the transcript for a YouTube video.")
    parser.add_argument("--url", required=True, help="YouTube link")
    parser.add_argument("--output", required=True, help="UTF-8 text file to be created")
    parser.add_argument("--languages", default=DEFAULT_LANGUAGES,
                        help="Subtitle languages in priority order (comma-separated regex)")
    args = parser.parse_args()
    try:
        transcript = get_transcript(args.url, args.languages)
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(transcript, encoding="utf-8")
        return 0
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
