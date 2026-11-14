# StudySide ✳

A calmer student dashboard with an automated YouTube Shorts creator.

**Live site:** https://wessonbrandon6-hue.github.io/studyside/

## Study dashboard
- Responsive desktop, tablet and mobile layout
- Add, complete and delete tasks; tasks persist in this browser with localStorage
- Daily focus tracking and a 25-minute / 5-minute Pomodoro timer
- Study buddy prompts for revision, active recall, quizzes and assignment planning
- Accessible controls and reduced-motion support

The study buddy is a local preset helper, not a live AI model. Browser tasks do not sync across devices.

## Daily YouTube Shorts automation
A GitHub Actions workflow is scheduled daily at 15:00 UTC (17:00 South Africa time) and can also be run manually. It creates an original vertical video with text cards and generated English narration, then uploads through YouTube Data API v3. The upload is public by default.

### One-time YouTube setup
1. In [Google Cloud Console](https://console.cloud.google.com/), create/select a project and enable YouTube Data API v3.
2. Configure OAuth consent and create an OAuth client ID (Desktop app).
3. Authorize the Google account that owns your channel with the scope https://www.googleapis.com/auth/youtube.upload and obtain a refresh token. Follow Google's [upload guide](https://developers.google.com/youtube/data/guides/uploading_a_video) and [OAuth guide](https://developers.google.com/youtube/data/guides/authentication).
4. In this repo open Settings → Secrets and variables → Actions → New repository secret. Add YOUTUBE_CLIENT_ID, YOUTUBE_CLIENT_SECRET and YOUTUBE_REFRESH_TOKEN.
5. Open Actions → StudySide Daily YouTube Short → Run workflow to test the first upload.

Keep OAuth values private. Never commit them or send them in chat. The workflow records published dates/topics in youtube/published.json after a successful upload to avoid repeat posts. Generated MP4 files are available as workflow artifacts for seven days.

**Important:** the workflow code is now in GitHub, but it cannot upload until the three secrets are configured and OAuth access is granted. Google controls API access and quotas. Review the first generated video and the topic library before relying on its educational claims. Edit YOUTUBE_PRIVACY_STATUS in the workflow if you prefer unlisted/private test uploads.

## Run locally
Open index.html in a browser. No frontend build is required.

For the video generator, install Python 3.11+, FFmpeg and youtube/requirements.txt dependencies, configure the three environment variables, then run python youtube/create_short.py.

## GitHub Actions
- .github/workflows/pages.yml deploys the site to GitHub Pages on pushes to main.
- .github/workflows/youtube-shorts.yml generates and uploads the daily Short.
