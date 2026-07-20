-- Phase 1 du plan ERP Okitaku Shop : module "Prêt de produits" + registre unifié
-- des sorties de stock + traçabilité complète des mouvements.
--
-- Cette migration est strictement additive : aucune colonne ni table existante
-- n'est supprimée ou renommée. L'ancien module "Prêts" (avances d'argent, table
-- `prets`) n'est pas touché — seul son libellé change côté interface.

-- =====================================================================
-- 1) Enrichissement de mouvements_stock pour la traçabilité et le
--    registre unifié des sorties (vente, prêt, campagne, casse, etc.)
-- =====================================================================

alter table public.mouvements_stock
  add column if not exists numero_auto text,
  add column if not exists type_sortie text,
  add column if not exists personne_concernee text,
  add column if not exists telephone text,
  add column if not exists motif text,
  add column if not exists source_table text,
  add column if not exists source_id uuid,
  add column if not exists stock_avant integer,
  add column if not exists stock_apres integer;

do $$ begin
  alter table public.mouvements_stock
    add constraint mouvements_stock_type_sortie_check
    check (type_sortie is null or type_sortie in (
      'vente','pret','campagne','cadeau','consommation_interne','perte','casse','retour_fournisseur','echantillon'
    ));
exception when duplicate_object then null; end $$;

create index if not exists idx_mouvements_stock_type_sortie on public.mouvements_stock(type_sortie);
create index if not exists idx_mouvements_stock_source on public.mouvements_stock(source_table, source_id);

create sequence if not exists public.mouvements_stock_numero_seq;

-- Trigger : numérote chaque mouvement, calcule le stock avant/après (traçabilité),
-- et par défaut classe toute sortie sans type explicite comme "vente" (comportement
-- historique de l'appli, préservé pour ne rien casser).
create or replace function public.trg_mouvements_stock_fill()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stock_avant integer;
begin
  if new.numero_auto is null then
    new.numero_auto := 'MVT-' || lpad(nextval('public.mouvements_stock_numero_seq')::text, 6, '0');
  end if;

  select coalesce(sum(quantite) filter (where type = 'entree'), 0)
       - coalesce(sum(quantite) filter (where type = 'sortie'), 0)
    into v_stock_avant
  from public.mouvements_stock
  where article_id = new.article_id;

  new.stock_avant := coalesce(v_stock_avant, 0);
  new.stock_apres := new.stock_avant + (case when new.type = 'entree' then new.quantite else -new.quantite end);

  if new.type = 'sortie' and new.type_sortie is null then
    new.type_sortie := 'vente';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_mouvements_stock_fill on public.mouvements_stock;
create trigger trg_mouvements_stock_fill
  before insert on public.mouvements_stock
  for each row execute function public.trg_mouvements_stock_fill();

-- Vue : registre unifié des sorties de stock (recherche/filtre/export)
create or replace view public.v_sorties_stock
with (security_invoker = true) as
select
  m.id, m.numero_auto, m.date,
  to_char(m.created_at, 'HH24:MI') as heure,
  m.article_id, a.code as article_code, a.libelle as article_libelle,
  m.quantite,
  (case when m.quantite > 0 then round(m.montant / m.quantite, 2) else 0 end) as prix_unitaire,
  m.montant as valeur_totale,
  m.personne_concernee, m.telephone, m.type_sortie, m.motif,
  m.created_by as utilisateur, m.justificatif_path, m.source_table, m.source_id,
  m.stock_avant, m.stock_apres, m.created_at
from public.mouvements_stock m
join public.articles a on a.id = m.article_id
where m.type = 'sortie'
order by m.created_at desc;

-- Vue : historique complet par produit (entrées, sorties, prêts, retours, ajustements)
create or replace view public.v_historique_produit
with (security_invoker = true) as
select
  m.id, m.article_id, a.code as article_code, a.libelle as article_libelle,
  m.date, m.created_at, m.created_by as utilisateur,
  case
    when m.type = 'entree' and m.source_table is null then 'Entrée / réassort'
    when m.type = 'entree' then 'Retour (' || coalesce(m.type_sortie, m.source_table) || ')'
    else initcap(coalesce(m.type_sortie, 'sortie'))
  end as action,
  m.type, m.type_sortie, m.quantite, m.stock_avant, m.stock_apres,
  (m.stock_apres - m.stock_avant) as difference,
  m.note as observation, m.source_table, m.source_id
from public.mouvements_stock m
join public.articles a on a.id = m.article_id
order by m.created_at desc;

-- =====================================================================
-- 2) Module Prêt de produits
-- =====================================================================

create sequence if not exists public.prets_produits_numero_seq;

create table if not exists public.prets_produits (
  id uuid primary key default gen_random_uuid(),
  numero text unique,
  date date not null default current_date,
  nom_beneficiaire text not null,
  telephone text,
  adresse text,
  observation text,
  date_retour_prevue date,
  date_retour_reelle date,
  statut text not null default 'en_cours' check (statut in ('en_cours','retourne','annule')),
  valeur_totale numeric not null default 0,
  created_by text default (auth.jwt() ->> 'email'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.prets_produits enable row level security;

drop policy if exists "prets_produits_team_all" on public.prets_produits;
create policy "prets_produits_team_all" on public.prets_produits
  for all to authenticated
  using (public.is_team_member())
  with check (public.is_team_member());

create index if not exists idx_prets_produits_deleted_at on public.prets_produits(deleted_at);
create index if not exists idx_prets_produits_statut on public.prets_produits(statut);

create or replace function public.trg_prets_produits_numero()
returns trigger language plpgsql as $$
begin
  if new.numero is null then
    new.numero := 'PRET-' || lpad(nextval('public.prets_produits_numero_seq')::text, 5, '0');
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_prets_produits_numero on public.prets_produits;
create trigger trg_prets_produits_numero
  before insert on public.prets_produits
  for each row execute function public.trg_prets_produits_numero();

create or replace function public.trg_prets_produits_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_prets_produits_touch on public.prets_produits;
create trigger trg_prets_produits_touch
  before update on public.prets_produits
  for each row execute function public.trg_prets_produits_touch();

create table if not exists public.prets_produits_lignes (
  id uuid primary key default gen_random_uuid(),
  pret_id uuid not null references public.prets_produits(id) on delete cascade,
  article_id uuid not null references public.articles(id),
  quantite integer not null check (quantite > 0),
  prix_unitaire numeric not null default 0,
  quantite_retournee integer not null default 0 check (quantite_retournee >= 0),
  created_at timestamptz not null default now()
);

alter table public.prets_produits_lignes enable row level security;

drop policy if exists "prets_produits_lignes_team_all" on public.prets_produits_lignes;
create policy "prets_produits_lignes_team_all" on public.prets_produits_lignes
  for all to authenticated
  using (public.is_team_member())
  with check (public.is_team_member());

create index if not exists idx_prets_produits_lignes_pret on public.prets_produits_lignes(pret_id);
create index if not exists idx_prets_produits_lignes_article on public.prets_produits_lignes(article_id);

-- ---------------------------------------------------------------------
-- RPC : créer un prêt de produits (atomique — vérifie le stock, insère
-- les lignes, sort le stock automatiquement, alimente le registre unifié)
-- ---------------------------------------------------------------------
create or replace function public.creer_pret_produits(
  p_nom_beneficiaire text,
  p_telephone text,
  p_adresse text,
  p_observation text,
  p_date date,
  p_date_retour_prevue date,
  p_lignes jsonb -- [{article_id, quantite, prix_unitaire}]
)
returns public.prets_produits
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pret public.prets_produits;
  v_ligne jsonb;
  v_article_id uuid;
  v_quantite integer;
  v_prix numeric;
  v_stock_dispo integer;
  v_total numeric := 0;
begin
  if not public.is_team_member() then
    raise exception 'Non autorisé';
  end if;
  if p_lignes is null or jsonb_array_length(p_lignes) = 0 then
    raise exception 'Au moins un produit est requis.';
  end if;
  if p_nom_beneficiaire is null or trim(p_nom_beneficiaire) = '' then
    raise exception 'Le nom du bénéficiaire est requis.';
  end if;

  insert into public.prets_produits (nom_beneficiaire, telephone, adresse, observation, date, date_retour_prevue)
  values (p_nom_beneficiaire, p_telephone, p_adresse, p_observation, coalesce(p_date, current_date), p_date_retour_prevue)
  returning * into v_pret;

  for v_ligne in select * from jsonb_array_elements(p_lignes) loop
    v_article_id := (v_ligne->>'article_id')::uuid;
    v_quantite := (v_ligne->>'quantite')::integer;
    v_prix := coalesce((v_ligne->>'prix_unitaire')::numeric, 0);

    if v_quantite is null or v_quantite <= 0 then
      raise exception 'Quantité invalide pour un des produits.';
    end if;

    select stock_restant into v_stock_dispo from public.v_articles_stock where id = v_article_id;
    if v_stock_dispo is null or v_stock_dispo < v_quantite then
      raise exception 'Stock insuffisant pour l''article %: disponible %, demandé %', v_article_id, coalesce(v_stock_dispo,0), v_quantite;
    end if;

    insert into public.prets_produits_lignes (pret_id, article_id, quantite, prix_unitaire)
    values (v_pret.id, v_article_id, v_quantite, v_prix);

    insert into public.mouvements_stock (
      article_id, date, type, quantite, montant, note,
      type_sortie, personne_concernee, telephone, motif, source_table, source_id
    ) values (
      v_article_id, coalesce(p_date, current_date), 'sortie', v_quantite, v_quantite * v_prix,
      'Prêt ' || v_pret.numero,
      'pret', p_nom_beneficiaire, p_telephone, 'Prêt de produits ' || v_pret.numero,
      'prets_produits', v_pret.id
    );

    v_total := v_total + (v_quantite * v_prix);
  end loop;

  update public.prets_produits set valeur_totale = v_total where id = v_pret.id returning * into v_pret;

  return v_pret;
end;
$$;

grant execute on function public.creer_pret_produits(text,text,text,text,date,date,jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- RPC : modifier les lignes d'un prêt en cours (uniquement si aucun
-- retour n'a encore été enregistré) — réajuste le stock automatiquement
-- ---------------------------------------------------------------------
create or replace function public.modifier_lignes_pret_produits(
  p_pret_id uuid,
  p_lignes jsonb
)
returns public.prets_produits
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pret public.prets_produits;
  v_ligne jsonb;
  v_article_id uuid;
  v_quantite integer;
  v_prix numeric;
  v_stock_dispo integer;
  v_total numeric := 0;
  v_deja_retourne integer;
  v_old record;
begin
  if not public.is_team_member() then raise exception 'Non autorisé'; end if;

  select * into v_pret from public.prets_produits where id = p_pret_id for update;
  if v_pret is null then raise exception 'Prêt introuvable'; end if;
  if v_pret.statut != 'en_cours' then raise exception 'Seul un prêt en cours peut être modifié.'; end if;

  select coalesce(sum(quantite_retournee),0) into v_deja_retourne
  from public.prets_produits_lignes where pret_id = p_pret_id;
  if v_deja_retourne > 0 then
    raise exception 'Ce prêt a déjà des retours enregistrés : modifie uniquement les informations générales, pas les produits.';
  end if;

  for v_old in select * from public.prets_produits_lignes where pret_id = p_pret_id loop
    insert into public.mouvements_stock (
      article_id, date, type, quantite, montant, note, source_table, source_id
    ) values (
      v_old.article_id, current_date, 'entree', v_old.quantite, v_old.quantite * v_old.prix_unitaire,
      'Correction / modification prêt ' || v_pret.numero, 'prets_produits', v_pret.id
    );
  end loop;
  delete from public.prets_produits_lignes where pret_id = p_pret_id;

  for v_ligne in select * from jsonb_array_elements(p_lignes) loop
    v_article_id := (v_ligne->>'article_id')::uuid;
    v_quantite := (v_ligne->>'quantite')::integer;
    v_prix := coalesce((v_ligne->>'prix_unitaire')::numeric, 0);

    if v_quantite is null or v_quantite <= 0 then
      raise exception 'Quantité invalide pour un des produits.';
    end if;

    select stock_restant into v_stock_dispo from public.v_articles_stock where id = v_article_id;
    if v_stock_dispo is null or v_stock_dispo < v_quantite then
      raise exception 'Stock insuffisant pour l''article %: disponible %, demandé %', v_article_id, coalesce(v_stock_dispo,0), v_quantite;
    end if;

    insert into public.prets_produits_lignes (pret_id, article_id, quantite, prix_unitaire)
    values (p_pret_id, v_article_id, v_quantite, v_prix);

    insert into public.mouvements_stock (
      article_id, date, type, quantite, montant, note,
      type_sortie, personne_concernee, telephone, motif, source_table, source_id
    ) values (
      v_article_id, current_date, 'sortie', v_quantite, v_quantite * v_prix,
      'Prêt ' || v_pret.numero || ' (modifié)',
      'pret', v_pret.nom_beneficiaire, v_pret.telephone, 'Prêt de produits ' || v_pret.numero || ' (modifié)',
      'prets_produits', p_pret_id
    );

    v_total := v_total + (v_quantite * v_prix);
  end loop;

  update public.prets_produits set valeur_totale = v_total where id = p_pret_id returning * into v_pret;
  return v_pret;
end;
$$;

grant execute on function public.modifier_lignes_pret_produits(uuid,jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- RPC : enregistrer un retour (partiel ou total) sur une ligne de prêt
-- ---------------------------------------------------------------------
create or replace function public.retourner_ligne_pret_produits(
  p_ligne_id uuid,
  p_quantite integer,
  p_note text
)
returns public.prets_produits
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ligne public.prets_produits_lignes;
  v_pret public.prets_produits;
  v_restant integer;
  v_total_lignes integer;
  v_total_retournees integer;
begin
  if not public.is_team_member() then
    raise exception 'Non autorisé';
  end if;

  select * into v_ligne from public.prets_produits_lignes where id = p_ligne_id for update;
  if v_ligne is null then raise exception 'Ligne de prêt introuvable'; end if;

  v_restant := v_ligne.quantite - v_ligne.quantite_retournee;
  if p_quantite is null or p_quantite <= 0 or p_quantite > v_restant then
    raise exception 'Quantité de retour invalide (restant à rendre : %)', v_restant;
  end if;

  select * into v_pret from public.prets_produits where id = v_ligne.pret_id for update;
  if v_pret.statut = 'annule' then raise exception 'Ce prêt est annulé.'; end if;

  update public.prets_produits_lignes
    set quantite_retournee = quantite_retournee + p_quantite
    where id = p_ligne_id;

  insert into public.mouvements_stock (
    article_id, date, type, quantite, montant, note, source_table, source_id
  ) values (
    v_ligne.article_id, current_date, 'entree', p_quantite, p_quantite * v_ligne.prix_unitaire,
    'Retour prêt ' || v_pret.numero || coalesce(' — ' || p_note, ''),
    'prets_produits', v_pret.id
  );

  select count(*), coalesce(sum(case when quantite_retournee >= quantite then 1 else 0 end), 0)
    into v_total_lignes, v_total_retournees
  from public.prets_produits_lignes where pret_id = v_pret.id;

  if v_total_retournees = v_total_lignes then
    update public.prets_produits
      set statut = 'retourne', date_retour_reelle = coalesce(date_retour_reelle, current_date)
      where id = v_pret.id
      returning * into v_pret;
  else
    select * into v_pret from public.prets_produits where id = v_pret.id;
  end if;

  return v_pret;
end;
$$;

grant execute on function public.retourner_ligne_pret_produits(uuid,integer,text) to authenticated;

-- ---------------------------------------------------------------------
-- RPC : annuler un prêt en cours (restitue automatiquement le stock dû)
-- ---------------------------------------------------------------------
create or replace function public.annuler_pret_produits(p_pret_id uuid)
returns public.prets_produits
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pret public.prets_produits;
  v_ligne record;
  v_restant integer;
begin
  if not public.is_team_member() then raise exception 'Non autorisé'; end if;

  select * into v_pret from public.prets_produits where id = p_pret_id for update;
  if v_pret is null then raise exception 'Prêt introuvable'; end if;
  if v_pret.statut != 'en_cours' then raise exception 'Seul un prêt en cours peut être annulé.'; end if;

  for v_ligne in select * from public.prets_produits_lignes where pret_id = p_pret_id loop
    v_restant := v_ligne.quantite - v_ligne.quantite_retournee;
    if v_restant > 0 then
      insert into public.mouvements_stock (
        article_id, date, type, quantite, montant, note, source_table, source_id
      ) values (
        v_ligne.article_id, current_date, 'entree', v_restant, v_restant * v_ligne.prix_unitaire,
        'Annulation prêt ' || v_pret.numero, 'prets_produits', v_pret.id
      );
      update public.prets_produits_lignes set quantite_retournee = quantite where id = v_ligne.id;
    end if;
  end loop;

  update public.prets_produits
    set statut = 'annule'
    where id = p_pret_id
    returning * into v_pret;

  return v_pret;
end;
$$;

grant execute on function public.annuler_pret_produits(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- RPC : suppression (corbeille) et restauration d'un prêt
-- ---------------------------------------------------------------------
create or replace function public.supprimer_pret_produits(p_pret_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pret public.prets_produits;
begin
  if not public.is_team_member() then raise exception 'Non autorisé'; end if;
  select * into v_pret from public.prets_produits where id = p_pret_id for update;
  if v_pret is null then raise exception 'Prêt introuvable'; end if;

  if v_pret.statut = 'en_cours' then
    perform public.annuler_pret_produits(p_pret_id);
  end if;

  update public.prets_produits set deleted_at = now() where id = p_pret_id;
end;
$$;

grant execute on function public.supprimer_pret_produits(uuid) to authenticated;

create or replace function public.restaurer_pret_produits(p_pret_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_team_member() then raise exception 'Non autorisé'; end if;
  update public.prets_produits set deleted_at = null where id = p_pret_id;
end;
$$;

grant execute on function public.restaurer_pret_produits(uuid) to authenticated;
