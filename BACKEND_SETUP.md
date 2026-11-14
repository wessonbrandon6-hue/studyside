# StudySide backend (optional)

## Current setup: free browser-only mode

StudySide is currently hosted as a static site on GitHub Pages. **No paid server has been created or deployed.** The Render deployment blueprint has been removed.

The GED Command Centre works without a backend:
- Subject topic checklists and mastery tracking
- Free subject video courses
- Built-in quick quizzes and timed practice exams
- Answer explanations and assessment history
- Study planner, notes and personal resource library
- Browser-based export and reports

The Student & Teacher Portal is paused because shared accounts, class enrolments and cross-device file sharing require an always-on backend.

## Optional self-hosting

The `backend/` folder contains an optional Node.js + Express + SQLite API for anyone who later has their own server or computer that can stay online. It is not needed for the static StudySide site.

To run it locally:
1. Install Node.js 20 or newer.
2. Open a terminal in `backend/`.
3. Run `npm install`.
4. Copy `.env.example` to `.env` and set a private random `JWT_SECRET` of at least 32 characters.
5. Run `npm start`.
6. The API health check is `http://localhost:3000/api/health`.

A local API is only reachable on the computer running it unless you deliberately configure networking. Do not expose it publicly without HTTPS, secure secret management, backups, account verification, abuse controls and a privacy review. Never commit `.env`, database files or uploaded documents.

## Important

- GitHub Pages cannot run Node.js server code.
- The browser-only GED tracker saves progress on the current device and browser; it does not automatically sync to other devices.
- The shared portal remains disabled until a backend is deliberately hosted.
- StudySide is an independent study aid, not an official GED Testing Service product. Check official test requirements and current syllabus information with the relevant exam provider.
