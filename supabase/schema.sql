-- StudySide shared backend: run this entire file in Supabase SQL Editor.
-- Security model: users sign up as students. Only an existing project owner/admin may promote teachers.
create extension if not exists pgcrypto;
create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null default '',
 role text not null default 'student' check (role in ('student','teacher','admin')),
 created_at timestamptz not null default now()
);
create table if not exists public.classes (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 description text not null default '',
 teacher_id uuid not null references public.profiles(id) on delete cascade,
 join_code text not null unique default upper(substr(encode(gen_random_bytes(8),'hex'),1,8)),
 created_at timestamptz not null default now()
);
create table if not exists public.class_members (
 class_id uuid not null references public.classes(id) on delete cascade,
 student_id uuid not null references public.profiles(id) on delete cascade,
 joined_at timestamptz not null default now(),
 primary key(class_id,student_id)
);
create table if not exists public.resources (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references public.profiles(id) on delete cascade,
 class_id uuid references public.classes(id) on delete cascade,
 title text not null,
 description text not null default '',
 subject text not null default 'General',
 storage_path text not null,
 file_name text not null,
 mime_type text not null default 'application/octet-stream',
 created_at timestamptz not null default now()
);
create table if not exists public.quizzes (
 id uuid primary key default gen_random_uuid(),
 author_id uuid not null references public.profiles(id) on delete cascade,
 class_id uuid references public.classes(id) on delete cascade,
 title text not null,
 subject text not null,
 description text not null default '',
 questions jsonb not null default '[]'::jsonb,
 published boolean not null default false,
 created_at timestamptz not null default now(),
 constraint quiz_questions_array check (jsonb_typeof(questions)='array')
);
create table if not exists public.quiz_attempts (
 id uuid primary key default gen_random_uuid(),
 quiz_id uuid not null references public.quizzes(id) on delete cascade,
 student_id uuid not null references public.profiles(id) on delete cascade,
 answers jsonb not null default '[]'::jsonb,
 score integer not null default 0 check(score between 0 and 100),
 submitted_at timestamptz not null default now()
);
create table if not exists public.announcements (
 id uuid primary key default gen_random_uuid(),
 class_id uuid not null references public.classes(id) on delete cascade,
 author_id uuid not null references public.profiles(id) on delete cascade,
 title text not null,
 body text not null,
 created_at timestamptz not null default now()
);
create or replace function public.is_teacher_of(target_class uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.classes c where c.id=target_class and c.teacher_id=auth.uid()) $$;
create or replace function public.is_class_member(target_class uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.class_members m where m.class_id=target_class and m.student_id=auth.uid()) or public.is_teacher_of(target_class) $$;
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$ begin insert into public.profiles(id,display_name,role) values(new.id,coalesce(new.raw_user_meta_data->>'display_name',''),'student'); return new; end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
alter table public.profiles enable row level security;
alter table public.classes enable row level security;
alter table public.class_members enable row level security;
alter table public.resources enable row level security;
alter table public.quizzes enable row level security;
alter table public.quiz_attempts enable row level security;
alter table public.announcements enable row level security;
-- Profiles: users can read their own profile; teachers can read students in their classes.
drop policy if exists "profile self read" on public.profiles;
create policy "profile self read" on public.profiles for select to authenticated using(id=auth.uid() or exists(select 1 from public.class_members m join public.classes c on c.id=m.class_id where m.student_id=profiles.id and c.teacher_id=auth.uid()));
drop policy if exists "profile self update" on public.profiles;
create policy "profile self update" on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid() and role=(select p.role from public.profiles p where p.id=auth.uid()));
-- Classes
drop policy if exists "class visible to members" on public.classes;
create policy "class visible to members" on public.classes for select to authenticated using(teacher_id=auth.uid() or public.is_class_member(id));
drop policy if exists "teacher creates class" on public.classes;
create policy "teacher creates class" on public.classes for insert to authenticated with check(teacher_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('teacher','admin')));
drop policy if exists "teacher updates own class" on public.classes;
create policy "teacher updates own class" on public.classes for update to authenticated using(teacher_id=auth.uid()) with check(teacher_id=auth.uid());
drop policy if exists "teacher deletes own class" on public.classes;
create policy "teacher deletes own class" on public.classes for delete to authenticated using(teacher_id=auth.uid());
-- Class memberships
drop policy if exists "members can view class roster" on public.class_members;
create policy "members can view class roster" on public.class_members for select to authenticated using(student_id=auth.uid() or public.is_teacher_of(class_id));
drop policy if exists "student joins with code" on public.class_members;
-- Join codes are validated only inside this function, never trusted from browser-side checks.
create or replace function public.join_class_with_code(input_code text)
returns uuid language plpgsql security definer set search_path=public
as $ declare target uuid; begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select id into target from public.classes where join_code=upper(trim(input_code));
 if target is null then raise exception 'Invalid class code'; end if;
 insert into public.class_members(class_id,student_id) values(target,auth.uid()) on conflict do nothing;
 return target;
end $;
drop policy if exists "teacher removes class members" on public.class_members;
create policy "teacher removes class members" on public.class_members for delete to authenticated using(public.is_teacher_of(class_id));
-- Resources: teachers share to a class; students can read class resources.
drop policy if exists "read class resources" on public.resources;
create policy "read class resources" on public.resources for select to authenticated using(owner_id=auth.uid() or (class_id is not null and public.is_class_member(class_id)));
drop policy if exists "teacher uploads resources" on public.resources;
create policy "teacher uploads resources" on public.resources for insert to authenticated with check(owner_id=auth.uid() and (class_id is null or public.is_teacher_of(class_id)));
drop policy if exists "owner deletes resources" on public.resources;
create policy "owner deletes resources" on public.resources for delete to authenticated using(owner_id=auth.uid());
-- Quizzes
drop policy if exists "read published class quizzes" on public.quizzes;
create policy "read published class quizzes" on public.quizzes for select to authenticated using(author_id=auth.uid() or (published=true and (class_id is null or public.is_class_member(class_id))));
drop policy if exists "teacher creates quizzes" on public.quizzes;
create policy "teacher creates quizzes" on public.quizzes for insert to authenticated with check(author_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('teacher','admin')) and (class_id is null or public.is_teacher_of(class_id)));
drop policy if exists "teacher edits own quizzes" on public.quizzes;
create policy "teacher edits own quizzes" on public.quizzes for update to authenticated using(author_id=auth.uid()) with check(author_id=auth.uid());
drop policy if exists "teacher deletes own quizzes" on public.quizzes;
create policy "teacher deletes own quizzes" on public.quizzes for delete to authenticated using(author_id=auth.uid());
-- Attempts: students can submit and read their own; teachers can read attempts for their class quizzes.
drop policy if exists "student reads own attempts teacher reads class" on public.quiz_attempts;
create policy "student reads own attempts teacher reads class" on public.quiz_attempts for select to authenticated using(student_id=auth.uid() or exists(select 1 from public.quizzes q where q.id=quiz_id and q.class_id is not null and public.is_teacher_of(q.class_id)));
drop policy if exists "student submits own attempt" on public.quiz_attempts;
create policy "student submits own attempt" on public.quiz_attempts for insert to authenticated with check(student_id=auth.uid() and exists(select 1 from public.quizzes q where q.id=quiz_id and q.published=true));
-- Announcements
drop policy if exists "class members read announcements" on public.announcements;
create policy "class members read announcements" on public.announcements for select to authenticated using(public.is_class_member(class_id));
drop policy if exists "teacher posts announcements" on public.announcements;
create policy "teacher posts announcements" on public.announcements for insert to authenticated with check(author_id=auth.uid() and public.is_teacher_of(class_id));
drop policy if exists "teacher deletes announcements" on public.announcements;
create policy "teacher deletes announcements" on public.announcements for delete to authenticated using(public.is_teacher_of(class_id));
-- Private object bucket; no public access. Object paths are prefixed by user UUID.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('studyside-resources','studyside-resources',false,20971520,array['application/pdf','image/png','image/jpeg','image/webp','text/plain','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.openxmlformats-officedocument.presentationml.presentation'])
on conflict(id) do nothing;
drop policy if exists "users upload own resource objects" on storage.objects;
create policy "users upload own resource objects" on storage.objects for insert to authenticated with check(bucket_id='studyside-resources' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "owners read own resource objects" on storage.objects;
create policy "class members read shared resource objects" on storage.objects for select to authenticated using(
 bucket_id='studyside-resources' and exists(
  select 1 from public.resources r where r.storage_path=name
  and (r.owner_id=auth.uid() or (r.class_id is not null and public.is_class_member(r.class_id)))
 )
);
drop policy if exists "owners delete own resource objects" on storage.objects;
create policy "owners delete own resource objects" on storage.objects for delete to authenticated using(bucket_id='studyside-resources' and (storage.foldername(name))[1]=auth.uid()::text);
-- To promote a teacher, run this manually as project owner after verifying the person's email:
-- update public.profiles set role='teacher' where id=(select id from auth.users where email='teacher@example.com');
