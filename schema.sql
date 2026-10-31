-- Chatly Supabase setup
-- Run this entire file in Supabase Dashboard > SQL Editor.
-- Then create a PUBLIC storage bucket named chat-images (Storage > New bucket).
-- Do not put your service_role key in the website.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (char_length(username) between 3 and 24),
  created_at timestamptz not null default now()
);

create or replace function public.create_profile_for_user()
returns trigger language plpgsql security definer set search_path = public
as $$
declare wanted text;
begin
  wanted := coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1));
  wanted := regexp_replace(wanted, '[^a-zA-Z0-9_]', '', 'g');
  if char_length(wanted) < 3 then wanted := 'user_' || substr(new.id::text,1,8); end if;
  insert into public.profiles(id, username)
  values(new.id, left(wanted,24))
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created_chatly on auth.users;
create trigger on_auth_user_created_chatly after insert on auth.users
for each row execute procedure public.create_profile_for_user();

create table if not exists public.servers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  description text not null default '',
  visibility text not null check (visibility in ('public','private')),
  owner_id uuid not null references auth.users(id) on delete cascade,
  invite_code text unique,
  created_at timestamptz not null default now(),
  check ((visibility='private' and invite_code is not null) or (visibility='public' and invite_code is null))
);

create table if not exists public.server_members (
  server_id uuid not null references public.servers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','member')),
  joined_at timestamptz not null default now(),
  primary key(server_id,user_id)
);

create table if not exists public.channels (
  id uuid primary key default gen_random_uuid(),
  server_id uuid not null references public.servers(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(server_id,name)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null default '' check (char_length(content) <= 4000),
  image_url text,
  created_at timestamptz not null default now(),
  check (content <> '' or image_url is not null)
);

create index if not exists messages_channel_created_idx on public.messages(channel_id,created_at);
create index if not exists memberships_user_idx on public.server_members(user_id);

alter table public.profiles enable row level security;
alter table public.servers enable row level security;
alter table public.server_members enable row level security;
alter table public.channels enable row level security;
alter table public.messages enable row level security;

drop policy if exists "Profiles visible to signed-in users" on public.profiles;
create policy "Profiles visible to signed-in users" on public.profiles for select to authenticated using (true);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile" on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());

drop policy if exists "Public servers or member servers are visible" on public.servers;
create policy "Public servers or member servers are visible" on public.servers for select to authenticated
using (owner_id=auth.uid() or visibility='public' or exists(select 1 from public.server_members m where m.server_id=id and m.user_id=auth.uid()));

drop policy if exists "Authenticated users create servers as owner" on public.servers;
create policy "Authenticated users create servers as owner" on public.servers for insert to authenticated with check (owner_id=auth.uid());

drop policy if exists "Owners update their servers" on public.servers;
create policy "Owners update their servers" on public.servers for update to authenticated using (owner_id=auth.uid()) with check (owner_id=auth.uid());

drop policy if exists "Members can see their memberships" on public.server_members;
create policy "Members can see their memberships" on public.server_members for select to authenticated using (user_id=auth.uid());

drop policy if exists "Join public servers or add self as owner" on public.server_members;
create policy "Join public servers or add self as owner" on public.server_members for insert to authenticated
with check (
  user_id=auth.uid() and (
    exists(select 1 from public.servers s where s.id=server_id and s.visibility='public')
    or exists(select 1 from public.servers s where s.id=server_id and s.owner_id=auth.uid())
  )
);

drop policy if exists "Members can read channels" on public.channels;
create policy "Members can read channels" on public.channels for select to authenticated
using (exists(select 1 from public.server_members m where m.server_id=server_id and m.user_id=auth.uid()));

drop policy if exists "Server owners create channels" on public.channels;
create policy "Server owners create channels" on public.channels for insert to authenticated
with check (created_by=auth.uid() and exists(select 1 from public.servers s where s.id=server_id and s.owner_id=auth.uid()));

drop policy if exists "Members can read messages" on public.messages;
create policy "Members can read messages" on public.messages for select to authenticated
using (exists(select 1 from public.channels c join public.server_members m on m.server_id=c.server_id where c.id=channel_id and m.user_id=auth.uid()));

drop policy if exists "Members can send messages as themselves" on public.messages;
create policy "Members can send messages as themselves" on public.messages for insert to authenticated
with check (user_id=auth.uid() and exists(select 1 from public.channels c join public.server_members m on m.server_id=c.server_id where c.id=channel_id and m.user_id=auth.uid()));

-- Private-server join uses an RPC so users cannot bypass invite-code checks.
create or replace function public.join_private_server(p_code text)
returns uuid language plpgsql security definer set search_path=public
as $$
declare target uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select id into target from public.servers
    where visibility='private' and invite_code=upper(trim(p_code));
  if target is null then raise exception 'Invalid invite code'; end if;
  insert into public.server_members(server_id,user_id,role)
    values(target,auth.uid(),'member') on conflict do nothing;
  return target;
end; $$;
revoke all on function public.join_private_server(text) from public;
grant execute on function public.join_private_server(text) to authenticated;

-- Storage: create bucket "chat-images" as PUBLIC in Dashboard > Storage.
-- These policies allow signed-in users to upload into a folder named with their auth UID.
drop policy if exists "Signed-in users upload own chat images" on storage.objects;
create policy "Signed-in users upload own chat images" on storage.objects for insert to authenticated
with check (bucket_id='chat-images' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Chat images are publicly readable" on storage.objects;
create policy "Chat images are publicly readable" on storage.objects for select to public
using (bucket_id='chat-images');

-- Enable realtime for new message events.
do $$
begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null;
when undefined_object then null;
end $$;
