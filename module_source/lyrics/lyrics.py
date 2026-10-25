import argparse
import os
import re
import sys
import threading
import json
import urllib.parse
import urllib.request

TIMEOUT_SECONDS = 30


def say_err(message):
    try:
        sys.stderr.write(message.encode("ascii", "replace").decode("ascii") + "\n")
        sys.stderr.flush()
    except Exception:
        pass


def start_watchdog():
    def _timeout():
        say_err("ERROR: timed out after %d seconds" % TIMEOUT_SECONDS)
        os._exit(1)

    timer = threading.Timer(TIMEOUT_SECONDS, _timeout)
    timer.daemon = True
    timer.start()


_TIMESTAMP = re.compile(r"^(?:\s*\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\])+\s*")


def tidy(text):
    lines = []
    for line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        lines.append(_TIMESTAMP.sub("", line).rstrip())
    return "\n".join(lines).strip()


def make_heading(title, artists):
    title = (title or "").strip()
    names = []
    for a in artists or []:
        name = a.get("name") if isinstance(a, dict) else str(a)
        if name:
            names.append(name.strip())
    artist = ", ".join(names)
    if title and artist:
        return "%s - %s" % (title, artist)
    return title or artist


def lyrics_of_video(yt, video_id):
    watch = yt.get_watch_playlist(videoId=video_id)
    browse_id = watch.get("lyrics") if isinstance(watch, dict) else None
    if not browse_id:
        return None
    data = yt.get_lyrics(browse_id)
    if not data:
        return None

    if isinstance(data, dict):
        text, source = data.get("lyrics"), data.get("source") or ""
    else:
        text, source = data, ""
    if not isinstance(text, str) or not text.strip():
        return None

    heading = ""
    tracks = watch.get("tracks") or []
    if tracks:
        heading = make_heading(tracks[0].get("title"), tracks[0].get("artists"))
    return heading, tidy(text), source


def search_youtube_music(video_id, query, state):
    from ytmusicapi import YTMusic
    yt = YTMusic()

    if video_id:
        try:
            found = lyrics_of_video(yt, video_id)
            state["ok"] += 1
            if found:
                return found
        except Exception as exc:
            state["errors"].append("YouTube Music ID: %s" % exc)

    if query:
        try:
            results = yt.search(query, filter="songs", limit=3)
            state["ok"] += 1
            for item in results or []:
                vid = item.get("videoId")
                if not vid:
                    continue
                found = lyrics_of_video(yt, vid)
                if found:
                    heading, text, source = found
                    if not heading:
                        heading = make_heading(item.get("title"), item.get("artists"))
                    return heading, text, source
        except Exception as exc:
            state["errors"].append("YouTube Music search: %s" % exc)

    return None


def search_lrclib(query, state):
    if not query:
        return None
    try:
        url = "https://lrclib.net/api/search?q=" + urllib.parse.quote(query)
        req = urllib.request.Request(url, headers={"User-Agent": "VDHMediaCenter/1.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            for item in data:
                lyrics = item.get("plainLyrics") or item.get("syncedLyrics")
                if lyrics:
                    heading = f"{item.get('trackName', '')} - {item.get('artistName', '')}"
                    state["ok"] += 1
                    return heading, tidy(lyrics), "LRCLIB"
    except Exception as exc:
        state["errors"].append("LRCLIB: %s" % exc)
    return None


def search_syncedlyrics(query, state):
    if not query:
        return None
    try:
        import syncedlyrics
        text = syncedlyrics.search(query)
        if text and text.strip():
            state["ok"] += 1
            return "", tidy(text), "syncedlyrics"
    except Exception as exc:
        state["errors"].append("syncedlyrics: %s" % exc)
    return None


def main():
    parser = argparse.ArgumentParser(description="Find song lyrics for VDH Media Center")
    parser.add_argument("--id", default="", help="YouTube video id")
    parser.add_argument("--query", default="", help="song name to search for")
    parser.add_argument("--output", required=True, help="text file to write the result to")
    args = parser.parse_args()

    video_id = re.sub(r"[^A-Za-z0-9_\-]", "", args.id or "")
    query = (args.query or "").strip()

    if not video_id and not query:
        say_err("ERROR: nothing to search for")
        return 1

    start_watchdog()
    state = {"ok": 0, "errors": []}
    result = None

    try:
        result = search_youtube_music(video_id, query, state)
    except Exception as exc:
        state["errors"].append("YouTube Music: %s" % exc)

    if result is None:
        result = search_lrclib(query, state)

    if result is None:
        result = search_syncedlyrics(query, state)

    if result is None:
        if state["ok"] == 0 and state["errors"]:
            say_err("ERROR: " + " | ".join(state["errors"]))
            return 1
        say_err("NOT_FOUND")
        return 2

    heading, text, source = result
    with open(args.output, "w", encoding="utf-8", newline="\n") as handle:
        if heading:
            handle.write("#HEADING: " + heading.replace("\n", " ") + "\n")
        handle.write(text + "\n")
        if source:
            handle.write("\n" + source.strip() + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())