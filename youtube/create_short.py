#!/usr/bin/env python3
"""Render an original StudySide vertical Short and upload it via YouTube Data API."""
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from PIL import Image, ImageDraw, ImageFont
from gtts import gTTS

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output"
STATE = ROOT / "youtube" / "published.json"
TOPICS = ROOT / "youtube" / "topics.json"
SCOPE = ["https://www.googleapis.com/auth/youtube.upload"]
W, H = 1080, 1920

def env(name):
    value = os.getenv(name, "").strip()
    if not value:
        raise SystemExit(f"Missing required GitHub Actions secret: {name}")
    return value

def get_font(size, bold=False):
    path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    if Path(path).exists():
        return ImageFont.truetype(path, size)
    return ImageFont.load_default()

def lines_for(draw, text, face, max_width):
    result, current = [], ""
    for word in text.split():
        candidate = (current + " " + word).strip()
        if draw.textbbox((0, 0), candidate, font=face)[2] <= max_width:
            current = candidate
        else:
            if current:
                result.append(current)
            current = word
    if current:
        result.append(current)
    return result

def centered(draw, text, y, face, fill, max_width):
    for line in lines_for(draw, text, face, max_width):
        box = draw.textbbox((0, 0), line, font=face)
        draw.text(((W - (box[2] - box[0])) // 2, y), line, font=face, fill=fill)
        y += box[3] - box[1] + 25
    return y

def make_card(number, label, heading, body, accent, path):
    image = Image.new("RGB", (W, H), "#17182b")
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((65, 100, W-65, H-100), radius=45, outline="#514a70", width=3)
    draw.rounded_rectangle((110, 150, 440, 220), radius=28, fill="#302b51")
    draw.text((140, 169), label.upper(), font=get_font(25, True), fill=accent)
    draw.text((W-190, 169), f"{number:02d}/06", font=get_font(24, True), fill="#aaa6c8")
    y = centered(draw, heading, 490, get_font(76, True), "#ffffff", W-190)
    y += 45
    draw.rounded_rectangle((W//2-60, y, W//2+60, y+8), radius=4, fill=accent)
    centered(draw, body, y+65, get_font(40), "#d7d7e7", W-210)
    draw.text((90, H-200), "STUDYSIDE  ✳  SMALL STEPS, BIG PROGRESS", font=get_font(22, True), fill="#aaa6c8")
    image.save(path, quality=94)

def render_video(cards, narration, duration, video):
    seconds = max(3.0, duration / len(cards))
    parts = []
    for i, card in enumerate(cards):
        part = OUT / f"part_{i:02d}.mp4"
        subprocess.run(["ffmpeg", "-y", "-loop", "1", "-i", str(card), "-t", f"{seconds:.2f}",
            "-vf", "scale=1080:1920,format=yuv420p", "-r", "30", "-an",
            "-c:v", "libx264", "-preset", "veryfast", str(part)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        parts.append(part)
    concat = OUT / "concat.txt"
    concat.write_text("".join(f"file '{p.as_posix()}'\n" for p in parts), encoding="utf-8")
    silent = OUT / "silent.mp4"
    subprocess.run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(concat), "-c", "copy", str(silent)],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["ffmpeg", "-y", "-i", str(silent), "-i", str(narration), "-map", "0:v:0", "-map", "1:a:0",
        "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", str(video)],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def choose_topic():
    data = json.loads(TOPICS.read_text(encoding="utf-8"))
    state = json.loads(STATE.read_text(encoding="utf-8"))
    today = datetime.now(timezone.utc).date().isoformat()
    if today in state.get("published_dates", []):
        raise SystemExit(f"Already published a Short for {today}; skipping duplicate.")
    used = set(state.get("published_topics", []))
    available = [t for t in data["topics"] if t["id"] not in used]
    if not available:
        state["published_topics"] = []
        available = data["topics"]
    topic = available[int(today.replace("-", "")) % len(available)]
    return topic, today, state, len(data["topics"])

def main():
    OUT.mkdir(exist_ok=True)
    topic, today, state, topic_count = choose_topic()
    accent = topic.get("accent", "#b7a8ff")
    cards_data = [
        ("THE STUDY RESET", topic["hook"], "A small change can make your next study session easier."),
        ("STEP 01", topic["steps"][0], "Start small. Make the first action easy to begin."),
        ("STEP 02", topic["steps"][1], "Keep your attention on one useful thing at a time."),
        ("STEP 03", topic["steps"][2], "Check what you learned instead of only rereading."),
        ("REMEMBER THIS", topic["takeaway"], "Progress comes from practice, not perfection."),
        ("YOUR NEXT MOVE", "Save this for your next study session.", "Follow StudySide for more practical study ideas.")
    ]
    cards = []
    for i, (label, heading, body) in enumerate(cards_data, 1):
        path = OUT / f"card_{i:02d}.jpg"
        make_card(i, label, heading, body, accent, path)
        cards.append(path)
    narration = OUT / "narration.mp3"
    gTTS(text=" ".join([topic["hook"]] + topic["steps"] + [topic["takeaway"]]), lang="en").save(str(narration))
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", str(narration)], check=True, capture_output=True, text=True)
    video = OUT / "studyside_daily_short.mp4"
    render_video(cards, narration, float(probe.stdout.strip()), video)

    creds = Credentials(token=None, refresh_token=env("YOUTUBE_REFRESH_TOKEN"),
        token_uri="https://oauth2.googleapis.com/token", client_id=env("YOUTUBE_CLIENT_ID"),
        client_secret=env("YOUTUBE_CLIENT_SECRET"), scopes=SCOPE)
    creds.refresh(Request())
    youtube = build("youtube", "v3", credentials=creds, cache_discovery=False)
    body = {"snippet": {"title": topic["title"][:95],
        "description": topic["description"] + "\n\nStudy smarter, one small step at a time. #StudyTips #StudyMotivation #Shorts",
        "tags": topic.get("tags", ["study tips", "productivity"]), "categoryId": "27", "defaultLanguage": "en"},
        "status": {"privacyStatus": os.getenv("YOUTUBE_PRIVACY_STATUS", "public"), "selfDeclaredMadeForKids": False}}
    request = youtube.videos().insert(part="snippet,status", body=body,
        media_body=MediaFileUpload(str(video), mimetype="video/mp4", chunksize=8*1024*1024, resumable=True))
    response = None
    while response is None:
        status, response = request.next_chunk()
        if status:
            print(f"Upload progress: {int(status.progress()*100)}%")
    video_id = response["id"]
    state.setdefault("published_dates", []).append(today)
    state.setdefault("published_topics", []).append(topic["id"])
    state["published_dates"] = state["published_dates"][-90:]
    state["published_topics"] = state["published_topics"][-topic_count:]
    STATE.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    url = f"https://www.youtube.com/shorts/{video_id}"
    summary = os.getenv("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(f"## StudySide Short published\n\n**{topic['title']}**\n\n[Watch the Short]({url})\n")
    print(f"Published: {url}")

if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        print(f"Rendering command failed: {exc}", file=sys.stderr)
        raise
