-- Import initial du tableau de stock fourni le 14/07/2026.
-- Ajuste ou supprime ce fichier si tu repars d'un stock vierge sur un autre projet Supabase.

insert into public.articles (code, libelle, prix_vente) values
('OKI0001','Kimono Demon Slayer',8000),
('OKI0002','Chapeau de Paille Luffy(Paille)',3500),
('OKI0002','Chapeau de Paille Luffy',3000),
('OKI0003','Chapeau Ace',4000),
('OKI0004','Katana (tous modèles)',4500),
('OKI0005','Pochette Grenouille Uzumaki',10000),
('OKI0006','Maillot Blue Lock',12000),
('OKI0007','Maillot Haikyu',12000),
('OKI0008','T-shirt Vintage',7000),
('OKI0009','Cosplay Naruto',7000),
('OKI0010','Cosplay Demon Slayer',15000),
('OKI0011','Tableaux PVC (tous formats)',2000),
('OKI0012','Tote Bag',3000),
('OKI0013','Porte-clés',3000),
('OKI0014','Tasse / Mug',1000),
('OKI0015','Boucles d''oreilles Demon Slayer',null),
('OKI0016','Sac à dos Anime big 3',7000),
('OKI0017','Light Box',2000),
('OKI0018','Masque',10000),
('OKI0019','Kimono Akatsuki',30000),
('OKI0020','Casquette SNK',30000),
('OKI0021','Bonnet',8000),
('OKI0022','Carte Demon Slayer',null),
('OKI0023','Cahier Death Note + Stylo',3500),
('OKI0024','Collier Death Note',1500),
('OKI0025','Pantalon',7000),
('OKI0026','Bambou',7000),
('OKI0027','Manga',5000),
('OKI0028','Katana Bambou',30000),
('OKI0029','Cosplay Naruto (2)',30000),
('OKI0030','Cosplay Nezuko',30000),
('OKI0031','Sac à dos Anime',null),
('OKI0032','Tote Bag (2)',null),
('OKI0035','Collier',3500),
('OKI0036','Bague Akatsuki',4000),
('OKI0037','Boucles Demon Slayer',2000),
('OKI0038','Light Box (2)',null),
('OKI0039','Tableau PVC 35x35',null)
on conflict (code, libelle) do nothing;

insert into public.mouvements_stock (article_id, date, type, quantite, montant, note)
select a.id, '2026-07-14', 'entree', v.qte, v.montant, 'Import initial (solde au 14/07/2026)'
from (values
  ('OKI0001','Kimono Demon Slayer',10,80000),
  ('OKI0002','Chapeau de Paille Luffy(Paille)',50,140000),
  ('OKI0002','Chapeau de Paille Luffy',120,330000),
  ('OKI0003','Chapeau Ace',60,240000),
  ('OKI0004','Katana (tous modèles)',19,40500),
  ('OKI0005','Pochette Grenouille Uzumaki',20,170000),
  ('OKI0008','T-shirt Vintage',23,161000),
  ('OKI0010','Cosplay Demon Slayer',16,210000),
  ('OKI0011','Tableaux PVC (tous formats)',131,262000),
  ('OKI0012','Tote Bag',120,0),
  ('OKI0013','Porte-clés',75,0),
  ('OKI0014','Tasse / Mug',7,0),
  ('OKI0015','Boucles d''oreilles Demon Slayer',100,0),
  ('OKI0016','Sac à dos Anime big 3',10,14000),
  ('OKI0017','Light Box',10,4000),
  ('OKI0018','Masque',50,20000),
  ('OKI0019','Kimono Akatsuki',8,0),
  ('OKI0023','Cahier Death Note + Stylo',50,17500),
  ('OKI0024','Collier Death Note',50,69000),
  ('OKI0025','Pantalon',6,14000),
  ('OKI0026','Bambou',7,35000),
  ('OKI0027','Manga',23,75000)
) as v(code, libelle, qte, montant)
join public.articles a on a.code = v.code and a.libelle = v.libelle;

insert into public.mouvements_stock (article_id, date, type, quantite, montant, note)
select a.id, '2026-07-14', 'sortie', v.qte, v.montant, 'Import initial (solde au 14/07/2026)'
from (values
  ('OKI0001','Kimono Demon Slayer',10,80000),
  ('OKI0002','Chapeau de Paille Luffy(Paille)',10,35000),
  ('OKI0002','Chapeau de Paille Luffy',10,30000),
  ('OKI0004','Katana (tous modèles)',10,45000),
  ('OKI0005','Pochette Grenouille Uzumaki',3,30000),
  ('OKI0009','Cosplay Naruto',19,133000),
  ('OKI0010','Cosplay Demon Slayer',4,60000),
  ('OKI0012','Tote Bag',120,360000),
  ('OKI0013','Porte-clés',75,225000),
  ('OKI0014','Tasse / Mug',7,7000),
  ('OKI0015','Boucles d''oreilles Demon Slayer',95,0),
  ('OKI0016','Sac à dos Anime big 3',8,56000),
  ('OKI0017','Light Box',8,16000),
  ('OKI0018','Masque',48,480000),
  ('OKI0019','Kimono Akatsuki',8,240000),
  ('OKI0021','Bonnet',8,64000),
  ('OKI0023','Cahier Death Note + Stylo',50,175000),
  ('OKI0024','Collier Death Note',4,6000),
  ('OKI0025','Pantalon',4,28000),
  ('OKI0026','Bambou',2,14000),
  ('OKI0027','Manga',8,40000)
) as v(code, libelle, qte, montant)
join public.articles a on a.code = v.code and a.libelle = v.libelle;
