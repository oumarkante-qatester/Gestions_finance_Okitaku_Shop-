-- Fournisseurs
create table if not exists public.fournisseurs (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  telephone text,
  email text,
  articles_fournis text,
  montant_du numeric not null default 0,
  note text,
  created_by text default (auth.jwt() ->> 'email'),
  created_at timestamptz not null default now()
);
alter table public.fournisseurs enable row level security;
create policy "fournisseurs_admin_only" on public.fournisseurs
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Prêts (à des employés/proches, remboursés ou non)
create table if not exists public.prets (
  id uuid primary key default gen_random_uuid(),
  beneficiaire text not null,
  montant numeric not null check (montant > 0),
  date date not null default current_date,
  statut text not null default 'non_rembourse' check (statut in ('rembourse','non_rembourse','partiel')),
  montant_rembourse numeric not null default 0,
  note text,
  created_by text default (auth.jwt() ->> 'email'),
  created_at timestamptz not null default now()
);
alter table public.prets enable row level security;
create policy "prets_admin_only" on public.prets
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Infos de contact / branding de la boutique (logo, réseaux, coordonnées) — un seul rang
create table if not exists public.shop_settings (
  id boolean primary key default true,
  logo_url text,
  email_contact text,
  telephone text,
  instagram text,
  wave_business text,
  constraint single_row check (id)
);
alter table public.shop_settings enable row level security;
create policy "shop_settings_team_read" on public.shop_settings
  for select to authenticated
  using (public.is_team_member());
create policy "shop_settings_admin_write" on public.shop_settings
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

insert into public.shop_settings (id, email_contact, telephone)
values (true, 'okitakushop@gmail.com', '784180088')
on conflict (id) do update set email_contact = excluded.email_contact, telephone = excluded.telephone;
