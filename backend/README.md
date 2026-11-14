# StudySide API

A self-hosted Node.js + Express + SQLite API. It does not use Supabase or another managed database.

## Local run
1. Install Node.js 20+.
2. From this folder run `npm install`.
3. Copy `.env.example` to `.env`, then set a unique `JWT_SECRET` (at least 32 characters).
4. Set `DATA_DIR=./data`.
5. Run `npm start`; health check is `http://localhost:3000/api/health`.

## Deploy
Use the included Dockerfile and Render blueprint as one supported host option. The blueprint provisions a persistent disk for SQLite and generated uploads. The service is not live until a hosting provider creates it and supplies its public URL. Set the frontend's `STUDYSIDE_API_URL` to that URL after deployment.

## API
- `POST /api/auth/register`, `POST /api/auth/login`, `GET /api/auth/me`
- `GET/POST /api/classes`, `POST /api/classes/join`
- `GET/POST /api/resources`, `GET /api/resources/:id/download`
- `GET/POST /api/quizzes`, `POST /api/quizzes/:id/attempts`
- `GET /api/teacher/dashboard`
- `GET/POST /api/announcements`

Protected endpoints require `Authorization: Bearer <token>`. Teacher roles are granted only to addresses explicitly listed in `TEACHER_EMAILS`; all other new accounts are students. Quiz answers are only stored server-side and are never returned by the quiz-list endpoint.

## Operations
Back up the entire `DATA_DIR` regularly. Keep the disk persistent, protect the JWT secret, use HTTPS, and review privacy, retention, abuse reporting and safeguarding before inviting real students. This is a starter deployment, not yet a production-audited school system.
