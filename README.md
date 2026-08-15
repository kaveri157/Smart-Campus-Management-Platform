Smart Campus Management Platform

Problem Statement 1 — DevFusion 4.0

A single portal for a college: students, faculty, coordinators and admins sign in and get their own view of attendance, assignments, events, placements, clubs, announcements and notifications.

Contents
What it does
Admin panel walkthrough
How to get admin access (read this first)
Tech stack
Run locally
Run with Docker
Documentation
Test accounts
Known limitations
What it does
Email + password and Google sign-in, with password reset
Role based access: student, faculty, coordinator, admin — enforced by Postgres RLS, not just the UI
Attendance: faculty open sessions and mark the roll, students self-mark and see subject-wise %
Assignments: faculty publish with a deadline, students submit a link + notes, faculty grade with marks and feedback
Events: coordinators/admins create events, students register and get a QR ticket pass, can cancel
Placements: coordinators/admins post drives, students apply (auto-attaches their resume link), track status, withdraw
Clubs: coordinators/admins register clubs, everyone can join or leave
Announcements with pinning, plus a notifications feed — mark read, mark all read, dismiss
Global search across courses, events, placements and announcements
Profile — fully editable (name, phone, roll no., department, semester, skills, links, resume, bio)
Settings — theme, email/push notification preferences and profile visibility persisted per-account, plus account deletion
Admin panel: institution stats, a users & performance tab (assign/revoke roles, edit a student's CGPA/semester, approve or revoke access), and a post announcement tab that publishes straight to the announcements feed
Admin panel walkthrough

Every new sign-up (email/password or Google) automatically gets the student role — see handle_new_user() in supabase/migrations/20260810072056_*.sql. There is no seeded admin account, so the first admin has to be promoted manually once (steps below). After that, promoting more admins is a click inside the app.

Once signed in as an admin, open Admin panel from the sidebar (this link only renders for the admin role):

Overview — live counts of departments, courses, events, placement drives, announcements and registered users.
Users & performance — every registered user with toggleable role chips (student / faculty / coordinator / admin) and inline fields for CGPA, semester and approval status. "Save performance" writes to profiles.cgpa / profiles.semester / profiles.is_approved; "Revoke access" clears a user's roles and marks them unapproved. This is also how you promote the next admin — just click the "Admin" role chip on any user's row.
Post announcement — a form (title, body, pin toggle) that inserts directly into the announcements table and appears immediately on the Announcements page for every signed-in user. This is the "advertisement" / notice-board feature — any user with the faculty, coordinator or admin role can post from here, not only admins (see the permission table in docs/API.md).

All of the above is enforced twice: the sidebar link only renders for the right roles, and the underlying Postgres Row Level Security policies reject the same writes from anyone who isn't authorized — even if someone calls the API directly. See docs/API.md.

How to get admin access (read this first)

There is a bootstrap step the very first time you set this project up, because nobody starts out as admin and the Admin panel is only reachable once you already have the role.

Step 1 — Create an account normally

Open the deployed site (or http://localhost:8080 when running locally), go to Sign up, and create an account with email + password or Google. This immediately gets you the student role — that's expected, everyone starts as a student.

Step 2 — Promote that account to admin (one-time, done in Supabase, not in the app)

You can't do this from the website yet, because there's no admin to click the "make admin" button for you. Do it once directly in your Supabase project:

Option A — Table Editor (no SQL needed)

Go to your Supabase project dashboard → Authentication → Users, and copy the UID of the account you signed up with in Step 1.
Go to Table Editor → user_roles → Insert row.
Set user_id to the UID you copied, and role to admin. Save.

Option B — SQL Editor (one line)

Go to SQL Editor in your Supabase dashboard and run:

sql
insert into user_roles (user_id, role)
select id, 'admin' from auth.users where email = 'your-signup-email@example.com';

That looks up your account by the email you signed up with and grants it the admin role.

Step 3 — Log back in (or refresh) on the website

Sign out and sign back in (or just refresh the page if your session is still active) at /auth. The Admin panel link now appears in the sidebar. From there:

Users & performance tab → promote any other user to admin, faculty or coordinator by clicking their role chip. No more manual SQL after this — it's all point-and-click from here on.
Post announcement tab → write a title + body, optionally pin it, click Post announcement. It appears instantly on the Announcements page and in the notifications context for every user.
A note on the "test accounts" some earlier docs may reference

Earlier drafts of this README listed ready-made logins like admin@smartcampus.test / Campus@1234. Those are not actually created by anything in this repository — Supabase Auth users (unlike every other table) can't be seeded from a plain SQL migration without the service-role key, which isn't checked into this project for security reasons. If you want that kind of one-command demo seeding for a hackathon judge to try quickly, see the optional seed script below; otherwise just follow Steps 1–3 above with your own email.

Optional: seed demo accounts for judges (service-role key required)

If you want four ready-made logins (student/faculty/coordinator/admin) for a demo, you can create them with a short script using the Supabase service-role key — never expose this key in the browser or commit it to git, only run it once locally:

bash
# .env.seed (local only, never commit)
SUPABASE_URL="https://your-project.supabase.co"
SUPABASE_SERVICE_ROLE_KEY="paste-service-role-key-from-Supabase-Settings-API"
javascript
// scripts/seed-demo-users.mjs — run with: node scripts/seed-demo-users.mjs
import { createClient } from "@supabase/supabase-js";
import "dotenv/config";

const admin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

const accounts = [
  { email: "student@smartcampus.test", role: "student" },
  { email: "faculty@smartcampus.test", role: "faculty" },
  { email: "coordinator@smartcampus.test", role: "coordinator" },
  { email: "admin@smartcampus.test", role: "admin" },
];

for (const { email, role } of accounts) {
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password: "Campus@1234",
    email_confirm: true,
  });
  if (error) { console.error(email, error.message); continue; }
  await admin.from("user_roles").upsert({ user_id: data.user.id, role }, { onConflict: "user_id,role" });
  console.log(`Created ${role}: ${email} / Campus@1234`);
}

This is optional and not included as a runnable file in this build (to avoid encouraging the service-role key to be pasted into a client-side project by mistake) — copy it into a local scripts/ folder yourself if you want it.

Tech stack
Frontend: React 19, TanStack Start + TanStack Router, TanStack Query, Tailwind CSS v4, shadcn/ui, lucide icons
Backend: TanStack Start server functions running on the edge
Database and auth: Supabase (PostgreSQL, Row Level Security, Google OAuth)
Build tooling: Vite 7, TypeScript, Bun / npm
Run locally
bash
git clone <this-repository-url>
cd smart-campus
npm install

Create a .env file in the root:

env
VITE_SUPABASE_URL="https://your-project.supabase.co"
VITE_SUPABASE_PUBLISHABLE_KEY="your-publishable-key"
VITE_SUPABASE_PROJECT_ID="your-project-id"
SUPABASE_URL="https://your-project.supabase.co"
SUPABASE_PUBLISHABLE_KEY="your-publishable-key"
SUPABASE_PROJECT_ID="your-project-id"

The SQL for every table, policy and seed row lives in supabase/migrations. Apply it to your Supabase project, then:

bash
npm run dev

The app runs on http://localhost:8080

Run with Docker
bash
docker compose up --build

Reads the same .env file as npm run dev and serves the production build on http://localhost:8080.

Documentation
docs/ARCHITECTURE.md — system architecture diagram and request flow
docs/ER-DIAGRAM.md — entity–relationship diagram for all 18 tables
docs/API.md — REST API reference (Supabase/PostgREST) and permission matrix
docs/openapi.yaml — OpenAPI 3.0 spec, importable into Swagger UI or Postman
LICENSE — MIT

Live link: See the deployment URL on the submission form (deployed from this repository).

Test accounts

There are no pre-seeded logins in this repository — see How to get admin access above for why (Supabase Auth users can't be created from a SQL migration) and for the two ways to get an admin account: promote your own sign-up once via Supabase, or run the optional seed script for four ready-made demo logins.

Once you (or the seed script) have an admin account, every other role can be created from the website itself: sign up normally (gets student), then have an admin open Admin panel → Users & performance and click the faculty / coordinator / admin chip on that user's row.


Known limitations
No payment flow in this build
Notification emails are not sent, notifications are in-app only (in-app + a QR pass image for events)
Attendance marking is manual for faculty (self-mark for students), there is no biometric capture
File uploads for assignment submissions/resumes accept links and text, not binary uploads to storage
Event QR codes are generated via a public QR-image API at render time, not stored as image files
Search is a straightforward multi table query, not full text ranked
Seed data is small, so charts look sparse on a fresh database
"Delete account" (self-service) and "Revoke access" (admin) clear roles and mark the profile unapproved; fully deleting the underlying Supabase Auth user requires the service-role key, which only runs on a trusted server, not in this client-only app
