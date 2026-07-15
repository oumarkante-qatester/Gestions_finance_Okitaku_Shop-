# Okita Shop — Gestion des ventes, du stock &amp; de la trésorerie

Tableau de bord en ligne pour gérer les ventes, le stock et la trésorerie d'Okita Shop, utilisable en équipe (à distance, en boutique ou en exposition).

## Fonctionnalités

- **Stock & ventes** : chaque article a un code, un libellé, un prix de vente. Le stock, les totaux d'achats/ventes et la valeur du stock sont calculés automatiquement à partir des mouvements (entrées = réassorts/achats, sorties = ventes).
- **Trésorerie** : mouvements généraux non liés à un article (loyer, salaires, transport, autres revenus/dépenses) — visible par les admins uniquement.
- **Rapport financier à la demande** : choisis une période (7 jours, 30 jours, ce mois, personnalisé) et génère un rapport complet (ventes, dépenses, résultat net, top articles, détail des mouvements), imprimable en PDF.
- **Équipe & rôles** :
  - **Admin** : accès complet (stock, ventes, trésorerie, rapports, gestion de l'équipe).
  - **Vendeur** : écran simplifié pour ajouter des ventes et des réassorts de stock pendant une expo ou en boutique, sans voir la trésorerie ni les rapports financiers.
- **Justificatifs** : possibilité de joindre une capture d'écran Wave / Orange Money (ou une photo de facture) à chaque mouvement de stock ou de trésorerie. Stockage privé, accessible uniquement à l'équipe connectée.
- **Mode clair/sombre**, impression de rapport, tout est enregistré en temps réel dans la base de données (aucune sauvegarde manuelle nécessaire).

## Stack technique

- Une seule page HTML statique (`index.html`), sans framework ni étape de build — facile à héberger n'importe où.
- [Supabase](https://supabase.com) comme backend : base de données Postgres, authentification par email/mot de passe, stockage de fichiers, et sécurité au niveau des lignes (Row Level Security) pour que chaque personne ne voie que ce à quoi elle a droit.
- Bibliothèque `@supabase/supabase-js` intégrée directement dans le fichier (pas de dépendance CDN externe au chargement).

## Configuration

Le fichier `index.html` contient déjà l'URL et la clé publique (`anon key`) du projet Supabase d'Okita Shop — cette clé est conçue pour être publique, la sécurité réelle est assurée par les politiques RLS côté base de données (voir `supabase/migrations/`).

Pour utiliser ce projet avec ta propre base Supabase :
1. Crée un projet sur [supabase.com](https://supabase.com).
2. Exécute les fichiers SQL du dossier `supabase/migrations/` dans l'ordre, dans l'éditeur SQL de Supabase.
3. Remplace `SUPABASE_URL` et `SUPABASE_ANON_KEY` en haut du `<script>` dans `index.html`.
4. Ajoute-toi comme admin dans la table `team_members`.

## Ajouter un membre de l'équipe

1. La personne crée son propre compte depuis l'écran de connexion (email + mot de passe).
2. Un admin va dans l'onglet **Équipe** du tableau de bord et ajoute son email avec le rôle souhaité (Admin ou Vendeur).

## Déploiement / hébergement en ligne

Ce projet est un site 100% statique : il peut être hébergé gratuitement sur **GitHub Pages** directement depuis ce dépôt (Settings → Pages → déployer depuis la branche `main`), sur Netlify, ou sur Cloudflare Pages. Voir la conversation avec Claude pour les recommandations de nom de domaine et d'hébergement annuel.

## Sécurité

- Chaque table est protégée par des politiques Row Level Security : un « Vendeur » ne peut ni lire ni écrire dans la trésorerie, seul un « Admin » le peut.
- Les captures de factures sont stockées dans un bucket privé, accessible uniquement aux comptes authentifiés de l'équipe.
- La clé `anon` visible dans le code est sans danger à exposer publiquement : c'est le mécanisme prévu par Supabase, tant que les politiques RLS sont actives (elles le sont).
