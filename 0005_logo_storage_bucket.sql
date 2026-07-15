insert into storage.buckets (id, name, public)
values ('logo', 'logo', true)
on conflict (id) do nothing;

drop policy if exists "logo_public_read" on storage.objects;
drop policy if exists "logo_admin_write" on storage.objects;

create policy "logo_public_read" on storage.objects
  for select to public
  using (bucket_id = 'logo');

create policy "logo_admin_write" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'logo' and public.is_admin());

create policy "logo_admin_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'logo' and public.is_admin());
