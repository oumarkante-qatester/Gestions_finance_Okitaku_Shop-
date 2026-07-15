-- Remplace admin_users par une vraie table d'équipe avec rôles
create table if not exists public.team_members (
  email text primary key,
  full_name text,
  role text not null default 'staff' check (role in ('admin', 'staff')),
  created_at timestamptz not null default now()
);

alter table public.team_members enable row level security;

-- migrer l'admin existant
insert into public.team_members (email, role, full_name)
values ('oumarkante.qatester@gmail.com', 'admin', 'Oumar')
on conflict (email) do update set role = 'admin';

create policy "team_members_self_read" on public.team_members
  for select to authenticated
  using (email = auth.jwt() ->> 'email');

create or replace function public.current_role()
returns text
language sql stable security definer set search_path = public
as $$
  select role from public.team_members where email = auth.jwt() ->> 'email';
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select public.current_role() = 'admin'; $$;

create or replace function public.is_team_member()
returns boolean language sql stable security definer set search_path = public
as $$ select public.current_role() in ('admin','staff'); $$;

-- admin gère l'équipe
create policy "team_members_admin_manage" on public.team_members
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Nettoyage ancienne table
drop policy if exists "articles_admin_all" on public.articles;
drop policy if exists "mouvements_stock_admin_all" on public.mouvements_stock;
drop policy if exists "mouvements_tresorerie_admin_all" on public.mouvements_tresorerie;

-- Articles & mouvements de stock : toute l'équipe (admin + staff)
create policy "articles_team_all" on public.articles
  for all to authenticated
  using (public.is_team_member())
  with check (public.is_team_member());

create policy "mouvements_stock_team_all" on public.mouvements_stock
  for all to authenticated
  using (public.is_team_member())
  with check (public.is_team_member());

-- Trésorerie générale : admin uniquement
create policy "mouvements_tresorerie_admin_only" on public.mouvements_tresorerie
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop table if exists public.admin_users cascade;

-- Traçabilité : qui a fait quoi
alter table public.mouvements_stock add column if not exists created_by text default (auth.jwt() ->> 'email');
alter table public.mouvements_tresorerie add column if not exists created_by text default (auth.jwt() ->> 'email');
alter table public.articles add column if not exists created_by text default (auth.jwt() ->> 'email');

-- Pièces jointes (captures Wave / Orange Money) liées à un mouvement
alter table public.mouvements_stock add column if not exists justificatif_path text;
alter table public.mouvements_tresorerie add column if not exists justificatif_path text;

-- Bucket de stockage privé pour les factures/captures
insert into storage.buckets (id, name, public)
values ('justificatifs', 'justificatifs', false)
on conflict (id) do nothing;

drop policy if exists "justificatifs_team_read" on storage.objects;
drop policy if exists "justificatifs_team_write" on storage.objects;
drop policy if exists "justificatifs_team_delete" on storage.objects;

create policy "justificatifs_team_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'justificatifs' and public.is_team_member());

create policy "justificatifs_team_write" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'justificatifs' and public.is_team_member());

create policy "justificatifs_team_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'justificatifs' and public.is_admin());

-- Vue de synthèse (inchangée, recréée pour référence)
create or replace view public.v_articles_stock
with (security_invoker = true) as
select
  a.id, a.code, a.libelle, a.prix_vente,
  coalesce(sum(m.quantite) filter (where m.type = 'entree'), 0)::int as entree,
  coalesce(sum(m.quantite) filter (where m.type = 'sortie'), 0)::int as sortie,
  (coalesce(sum(m.quantite) filter (where m.type = 'entree'), 0)
   - coalesce(sum(m.quantite) filter (where m.type = 'sortie'), 0))::int as stock_restant,
  coalesce(sum(m.montant) filter (where m.type = 'entree'), 0) as montant_total_achats,
  coalesce(sum(m.montant) filter (where m.type = 'sortie'), 0) as montant_total_ventes,
  ((coalesce(sum(m.quantite) filter (where m.type = 'entree'), 0)
    - coalesce(sum(m.quantite) filter (where m.type = 'sortie'), 0)) * coalesce(a.prix_vente, 0)) as valeur_stock,
  case when (coalesce(sum(m.quantite) filter (where m.type = 'entree'), 0)
    - coalesce(sum(m.quantite) filter (where m.type = 'sortie'), 0)) > 0
    then 'Vente possible' else 'Vente impossible' end as statut
from public.articles a
left join public.mouvements_stock m on m.article_id = a.id
group by a.id, a.code, a.libelle, a.prix_vente;
