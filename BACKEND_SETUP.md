# StudySide backend setup (self-hosted)

StudySide now uses its own Node.js API and SQLite database. The portal no longer calls Supabase.

## What is included
- Password-hashed student and teacher accounts (bcrypt).
- Signed API tokens and protected routes.
- Classes, secure join codes and enrolments.
- Private file uploads and authenticated downloads (20 MB limit).
- Teacher-created quizzes, server-side grading and saved attempts.
- Teacher dashboard and class announcements.
- SQLite database stored on a persistent disk.

## Deploy the API
1. The frontend stays on GitHub Pages. The API must run on a Node.js host or your own server; GitHub Pages cannot run a backend.
2. Deploy the repository backend/ directory using backend/Dockerfile. The root render.yaml is a Render deployment blueprint and uses a persistent disk. Render Starter and persistent disk resources are paid; check current pricing before deploying.
3. Set JWT_SECRET to a unique random secret of at least 32 characters. Set DATA_DIR to a directory on the persistent disk (the blueprint uses /app/backend/data).
4. Set ALLOWED_ORIGINS to https://wessonbrandon6-hue.github.io (comma-separated if you add another frontend origin).
5. After deployment, check https://YOUR-API-HOST/api/health.
6. Edit api-config.js and set STUDYSIDE_API_URL to the API origin, without a trailing slash. Commit; GitHub Pages redeploys the frontend.

## Local development
- Install Node.js 20 or newer.
- In backend/, run npm install.
- Copy .env.example to .env and set a long random JWT_SECRET.
- Run npm start; API health check is http://localhost:3000/api/health.
- Keep DATA_DIR on a persistent disk. Back up the entire directory.

## Teacher access
Every public signup creates a student account. The site owner promotes a verified teacher account from the backend host shell after the teacher has registered:

    cd backend
    npm run promote-teacher -- teacher@example.com

Do not expose server shell access or the database file to teachers or students.

## API routes
- POST /api/auth/register, POST /api/auth/login, GET /api/auth/me
- GET/POST /api/classes, POST /api/classes/join
- GET/POST /api/resources, GET /api/resources/:id/download
- GET/POST /api/quizzes, POST /api/quizzes/:id/attempts
- GET /api/teacher/dashboard
- GET/POST /api/announcements

Protected routes require Authorization: Bearer token.

## Important current limitations
- This is an initial self-hosted backend, not a fully production-audited school platform.
- Email verification and self-service password reset are not implemented yet.
- Tokens expire after seven days; users sign in again after expiry.
- SQLite and uploaded files live on the persistent disk. Back up that disk regularly.
- Add monitoring, automated backups, account verification, abuse reporting, data-retention controls and a privacy policy before inviting a school or minors.
- Use HTTPS and keep JWT_SECRET private. Never commit environment files, database files or uploaded documents.
