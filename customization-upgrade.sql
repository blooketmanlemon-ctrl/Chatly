-- Chatly customization upgrade: additive only; existing accounts/messages stay intact.
alter table public.profiles add column if not exists display_name text;
alter table public.profiles add column if not exists avatar_url text;
update public.profiles set display_name = username where display_name is null;

insert into storage.buckets (id, name, public)
values ('chat-avatars', 'chat-avatars', true)
on conflict (id) do update set public = true;

drop policy if exists "Chatly avatar images are publicly viewable" on storage.objects;
create policy "Chatly avatar images are publicly viewable"
on storage.objects for select to public
using (bucket_id = 'chat-avatars');

drop policy if exists "Users upload their own Chatly avatars" on storage.objects;
create policy "Users upload their own Chatly avatars"
on storage.objects for insert to authenticated
with check (bucket_id = 'chat-avatars' and (storage.foldername(name))[1] = auth.uid()::text);
