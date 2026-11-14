-- StudySide shared backend: run this entire file in Supabase SQL Editor.
-- Security model: users sign up as students. Only an existing project owner/admin may promote teachers.
create extension if not exists pgcrypto;
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;
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
create or replace function private.is_teacher_of(target_class uuid)
returns boolean language sql stable security definer set search_path=public
as $ select auth.uid() is not null and exists(select 1 from public.classes c where c.id=target_class and c.teacher_id=auth.uid()) $;
create or replace function private.is_class_member(target_class uuid)
returns boolean language sql stable security definer set search_path=public, private
as $ select auth.uid() is not null and (exists(select 1 from public.class_members m where m.class_id=target_class and m.student_id=auth.uid()) or private.is_teacher_of(target_class)) $;
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
create policy "profile self update" on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create or replace function public.prevent_profile_role_escalation()
returns trigger language plpgsql set search_path=public
as $ begin
 if new.role is distinct from old.role and auth.uid() is not null then
  raise exception 'Profile roles can only be changed by a project administrator';
 end if;
 return new;
end $;
drop trigger if exists protect_profile_role on public.profiles;
create trigger protect_profile_role before update on public.profiles
for each row execute function public.prevent_profile_role_escalation();
-- Classes
drop policy if exists "class visible to members" on public.classes;
create policy "class visible to members" on public.classes for select to authenticated using(teacher_id=auth.uid() or private.is_class_member(id));
drop policy if exists "teacher creates class" on public.classes;
create policy "teacher creates class" on public.classes for insert to authenticated with check(teacher_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('teacher','admin')));
drop policy if exists "teacher updates own class" on public.classes;
create policy "teacher updates own class" on public.classes for update to authenticated using(teacher_id=auth.uid()) with check(teacher_id=auth.uid());
drop policy if exists "teacher deletes own class" on public.classes;
create policy "teacher deletes own class" on public.classes for delete to authenticated using(teacher_id=auth.uid());
-- Class memberships
drop policy if exists "members can view class roster" on public.class_members;
create policy "members can view class roster" on public.class_members for select to authenticated using(student_id=auth.uid() or private.is_teacher_of(class_id));
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
create policy "teacher removes class members" on public.class_members for delete to authenticated using(private.is_teacher_of(class_id));
-- Resources: teachers share to a class; students can read class resources.
drop policy if exists "read class resources" on public.resources;
create policy "read class resources" on public.resources for select to authenticated using(owner_id=auth.uid() or (class_id is not null and private.is_class_member(class_id)));
drop policy if exists "teacher uploads resources" on public.resources;
create policy "teacher uploads resources" on public.resources for insert to authenticated with check(owner_id=auth.uid() and (class_id is null or private.is_teacher_of(class_id)));
drop policy if exists "owner deletes resources" on public.resources;
create policy "owner deletes resources" on public.resources for delete to authenticated using(owner_id=auth.uid());
-- Quizzes
drop policy if exists "read published class quizzes" on public.quizzes;
create policy "read published class quizzes" on public.quizzes for select to authenticated using(author_id=auth.uid() or (published=true and (class_id is null or private.is_class_member(class_id))));
drop policy if exists "teacher creates quizzes" on public.quizzes;
create policy "teacher creates quizzes" on public.quizzes for insert to authenticated with check(author_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('teacher','admin')) and (class_id is null or private.is_teacher_of(class_id)));
drop policy if exists "teacher edits own quizzes" on public.quizzes;
create policy "teacher edits own quizzes" on public.quizzes for update to authenticated using(author_id=auth.uid()) with check(author_id=auth.uid());
drop policy if exists "teacher deletes own quizzes" on public.quizzes;
create policy "teacher deletes own quizzes" on public.quizzes for delete to authenticated using(author_id=auth.uid());
-- Attempts: students can submit and read their own; teachers can read attempts for their class quizzes.
drop policy if exists "student reads own attempts teacher reads class" on public.quiz_attempts;
create policy "student reads own attempts teacher reads class" on public.quiz_attempts for select to authenticated using(student_id=auth.uid() or exists(select 1 from public.quizzes q where q.id=quiz_id and q.class_id is not null and private.is_teacher_of(q.class_id)));
drop policy if exists "student submits own attempt" on public.quiz_attempts;
create policy "student submits own attempt" on public.quiz_attempts for insert to authenticated with check(
 student_id=auth.uid() and exists(
  select 1 from public.quizzes q where q.id=quiz_id and q.published=true
  and (q.class_id is null or private.is_class_member(q.class_id))
 )
);
-- Announcements
drop policy if exists "class members read announcements" on public.announcements;
create policy "class members read announcements" on public.announcements for select to authenticated using(private.is_class_member(class_id));
drop policy if exists "teacher posts announcements" on public.announcements;
create policy "teacher posts announcements" on public.announcements for insert to authenticated with check(author_id=auth.uid() and private.is_teacher_of(class_id));
drop policy if exists "teacher deletes announcements" on public.announcements;
create policy "teacher deletes announcements" on public.announcements for delete to authenticated using(private.is_teacher_of(class_id));
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
  and (r.owner_id=auth.uid() or (r.class_id is not null and private.is_class_member(r.class_id)))
 )
);
drop policy if exists "owners delete own resource objects" on storage.objects;
create policy "owners delete own resource objects" on storage.objects for delete to authenticated using(bucket_id='studyside-resources' and (storage.foldername(name))[1]=auth.uid()::text);
-- To promote a teacher, run this manually as project owner after verifying the person's email:
-- update public.profiles set role='teacher' where id=(select id from auth.users where email='teacher@example.com');


-- Security and Data API hardening (November 2026)
-- Explicit grants are required for projects where public-schema tables are not
-- automatically exposed through the Data API. RLS remains the row-level gate.
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.profiles, public.classes,
 public.class_members, public.resources, public.quizzes,
 public.quiz_attempts, public.announcements to authenticated;

-- Never allow a browser client to insert its own claimed quiz score.
drop policy if exists "student submits own attempt" on public.quiz_attempts;

-- Keep the answer-key column inaccessible through direct table queries.
revoke select on public.quizzes from authenticated;
grant select (id, author_id, class_id, title, subject, description, published, created_at)
on public.quizzes to authenticated;

-- Return only questions without answer keys through a narrowly scoped RPC.
drop view if exists public.student_quizzes;
create or replace function public.get_available_quizzes()
returns table(
 id uuid, author_id uuid, class_id uuid, title text, subject text,
 description text, questions jsonb, published boolean, created_at timestamptz
)
language sql stable security definer set search_path=public, private
as $
 select q.id, q.author_id, q.class_id, q.title, q.subject, q.description,
        coalesce((
          select jsonb_agg(item - 'answer' order by ord)
          from jsonb_array_elements(q.questions) with ordinality as x(item, ord)
        ), '[]'::jsonb),
        q.published, q.created_at
 from public.quizzes q
 where auth.uid() is not null
   and (q.author_id=auth.uid() or (q.published=true and (q.class_id is null or private.is_class_member(q.class_id))))
$;

-- Grade answers on the server. The browser can submit choices, never a score.
create or replace function public.submit_quiz_attempt(target_quiz uuid, submitted_answers jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  quiz_questions jsonb;
  question_count integer;
  correct_count integer := 0;
  answer_index integer;
  i integer;
  final_score integer;
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;
  if jsonb_typeof(submitted_answers) <> 'array' then
    raise exception 'Answers must be an array';
  end if;

  select q.questions into quiz_questions
  from public.quizzes q
  where q.id = target_quiz
    and q.published = true
    and (q.class_id is null or private.is_class_member(q.class_id));

  if quiz_questions is null then
    raise exception 'Quiz not found or not available to this account';
  end if;

  question_count := jsonb_array_length(quiz_questions);
  if question_count = 0 or jsonb_array_length(submitted_answers) <> question_count then
    raise exception 'Answer count does not match quiz';
  end if;

  for i in 0..question_count - 1 loop
    answer_index := coalesce((submitted_answers ->> i)::integer, -1);
    if answer_index = (quiz_questions -> i ->> 'answer')::integer then
      correct_count := correct_count + 1;
    end if;
  end loop;

  final_score := round(100.0 * correct_count / question_count)::integer;
  insert into public.quiz_attempts(quiz_id, student_id, answers, score)
  values(target_quiz, auth.uid(), submitted_answers, final_score);

  return final_score;
end;
$$;

-- These helpers are only intended for authenticated RLS evaluation.
revoke all on function private.is_teacher_of(uuid) from public, anon;
revoke all on function private.is_class_member(uuid) from public, anon;
revoke all on function public.join_class_with_code(text) from public, anon;
revoke all on function public.submit_quiz_attempt(uuid, jsonb) from public, anon;
revoke all on function public.get_available_quizzes() from public, anon;
grant execute on function private.is_teacher_of(uuid) to authenticated;
grant execute on function private.is_class_member(uuid) to authenticated;
grant execute on function public.join_class_with_code(text) to authenticated;
grant execute on function public.submit_quiz_attempt(uuid, jsonb) to authenticated;
grant execute on function public.get_available_quizzes() to authenticated;
