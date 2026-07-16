-- À exécuter une seule fois dans Supabase → SQL Editor
-- Ajoute la colonne nécessaire pour stocker la clé API Wave Checkout.

alter table shop_settings
  add column if not exists wave_api_key text;
