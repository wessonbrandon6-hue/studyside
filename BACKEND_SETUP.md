# StudySide cloud backend setup

This repository now includes a Supabase-backed campus portal. GitHub Pages hosts the frontend; Supabase provides accounts, database, private file storage and class data.

## What is included
- Student email/password accounts and password reset.
- Student profiles; new accounts are always students.
- Teacher-created classes and join codes.
- Private cloud file uploads shared to a class (20 MB limit).
- Published multiple-choice quizzes and saved student attempts.
- Teacher dashboard with class counts and recent quiz attempts.
- Row-level security policies and a private storage bucket.
- Server-side quiz grading; student quiz responses do not include answer keys.
- Explicit Data API grants for projects created with Supabase's newer default exposure settings.
- Authorization helper functions kept in a non-exposed `private` schema; profile role changes are protected.

## One-time setup
1. Create a Supabase project in your own account. Because the site is public, only use a project you control. Follow the provider's age and parental-consent requirements.
2. Open the Supabase SQL Editor and run the latest complete file `supabase/schema.sql` from this repository. It includes explicit Data API grants and the quiz-security updates.
3. In Supabase project settings, copy the **Project URL** and **anon/public key**. Do not use the service_role key.
4. Edit `supabase-config.js` in this repository and replace the two placeholders with the Project URL and anon/public key.
5. Commit the change. GitHub Pages will redeploy automatically.
6. In Supabase Authentication → URL Configuration, set the Site URL to `https://wessonbrandon6-hue.github.io` and add `https://wessonbrandon6-hue.github.io/studyside/portal.html` to Redirect URLs.
7. Create a student account in the portal. To promote a verified teacher, use the SQL Editor as project owner:
   ```sql
   update public.profiles
   set role='teacher'
   where id=(select id from auth.users where email='teacher@example.com');
   ```
   Replace the email with the verified teacher's account. Never let users choose their own teacher role.
8. Teacher signs in, creates a class, shares the join code, uploads materials and publishes quizzes.

## Pages
- GED learning lab: `ged.html`
- Connected campus portal: `portal.html`
- Backend schema: `supabase/schema.sql`

## Security notes
- The browser uses only the Supabase anon/public key. Never expose a service_role key.
- SQL enables row-level security. Keep it enabled.
- Storage is private and the portal issues short-lived signed download links.
- New accounts cannot promote themselves to teacher; a database trigger also blocks self-service role changes.
- Published quiz answer keys are hidden from the student-facing view and attempts are graded by a server-side database function.
- This is a starter school portal, not a complete school information system. Review policies, moderation, retention, backups, child-safety and applicable privacy law before inviting real students.
- Student accounts may require parental/guardian involvement depending on the provider's terms and local law.
- GitHub Pages is static hosting; Supabase is the separate cloud backend.
