# StudySide Firebase setup (free Spark plan)

This repository is prepared with a restrictive Firestore rules starter and a
browser config template. Firebase is **not connected or live yet**.

## What must happen in Firebase Console

1. Create a Firebase project and stay on the **Spark (free)** plan. Do not add a
   billing account or enable paid products.
2. Register a Web app in Project settings.
3. Enable Authentication > Sign-in method > Email/Password.
4. Create a Cloud Firestore database. Choose a region appropriate for your users.
5. Publish the rules from this repository's `firestore.rules` file.
6. Copy `firebase-config.example.js` to `firebase-config.js` and fill it with
   the Web App config from Project settings.
7. Add `firebase-config.js` to `.gitignore` if you do not want your project
   identifiers committed. The web config is not an admin secret, but keeping
   project-specific settings out of the public repo makes configuration easier
   to manage.

## Important security boundary

The Firestore rules currently allow each signed-in user to read and write only
their own `users/{uid}` document and subcollection. Public content is read-only.
Shared classes are read-only for signed-in users and cannot be written by browser
clients. Teacher roles, class membership, uploads, and quiz publishing must not
be enabled until they are enforced with trusted server-side authorization or
verified custom claims.

Never put a Firebase service-account JSON file, Admin SDK private key, JWT
secret, or student password in this repository.

## Current app status

The existing Student & Teacher Portal still expects the separate StudySide API
for class management, uploads, announcements, and published quizzes. Adding
Firebase project config alone does not activate those features. Authentication
and student progress sync still need to be wired into the frontend and tested
against your actual Firebase project before students use it.

## What I need to finish the connection

After you create the Firebase Web App, provide the Web App config values (the
`firebaseConfig` object). Do not send passwords, service-account keys, or
private credentials. I can then wire the client-side email/password sign-in and
per-student progress sync into StudySide.
