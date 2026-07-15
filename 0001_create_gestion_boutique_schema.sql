-- Table des administrateurs autorisés à utiliser le tableau de bord de gestion
create table if not exists public.admin_users (
  email text primary key
);

insert into public.admin_users (email) values ('oumarkante.qatester@gmail.com')
on conflict (email) do nothing;

alter table public.admin_users enable row level security;

create policy "admin_users_self_read" on public.admin_users
  for select
  to authenticated
  using (email = auth.jwt() ->> 'email');

-- Fonction utilitaire: l'utilisateur connecté est-il un admin autorisé ?
create or replace function public.is_dashboard_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admin_users where email = auth.jwt() ->> 'email'
  );
$$;

-- Catalogue des articles (produits physiques de la boutique)
create table if not exists public.articles (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  libelle text not null,
  prix_vente numeric,
  created_at timestamptz not null default now(),
  unique (code, libelle)
);

alter table public.articles enable row level security;

create policy "articles_admin_all" on public.articles
  for all
  to authenticated
  using (public.is_dashboard_admin())
  with check (public.is_dashboard_admin());

-- Mouvements de stock (entrées = achats/réassorts, sorties = ventes)
create table if not exists public.mouvements_stock (
  id uuid primary key default gen_random_uuid(),
  article_id uuid not null references public.articles(id) on delete cascade,
  date date not null default current_date,
  type text not null check (type in ('entree', 'sortie')),
  quantite integer not null check (quantite > 0),
  montant numeric not null default 0,
  note text,
  created_at timestamptz not null default now()
);

alter table public.mouvements_stock enable row level security;

create policy "mouvements_stock_admin_all" on public.mouvements_stock
  for all
  to authenticated
  using (public.is_dashboard_admin())
  with check (public.is_dashboard_admin());

create index if not exists idx_mouvements_stock_article on public.mouvements_stock(article_id);
create index if not exists idx_mouvements_stock_date on public.mouvements_stock(date);

-- Mouvements de trésorerie généraux (loyer, salaires, transport, autres revenus...) non liés à un article
create table if not exists public.mouvements_tresorerie (
  id uuid primary key default gen_random_uuid(),
  date date not null default current_date,
  type text not null check (type in ('entree', 'sortie')),
  categorie text not null default 'Autre',
  description text,
  montant numeric not null check (montant > 0),
  created_at timestamptz not null default now()
);

alter table public.mouvements_tresorerie enable row level security;

create policy "mouvements_tresorerie_admin_all" on public.mouvements_tresorerie
  for all
  to authenticated
  using (public.is_dashboard_admin())
  with check (public.is_dashboard_admin());

create index if not exists idx_mouvements_tresorerie_date on public.mouvements_tresorerie(date);

-- Vue de synthèse par article (stock, achats, ventes, valeur du stock calculés dynamiquement)
create or replace view public.v_articles_stock
with (security_invoker = true) as
select
  a.id,
  a.code,
  a.libelle,
  a.prix_vente,
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
