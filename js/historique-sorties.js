/* ==========================================================================
   HISTORIQUE DES SORTIES DE STOCK — registre unifié (ES module)
   Lecture seule : alimenté automatiquement par ventes, prêts, campagnes, etc.
   via le trigger SQL sur mouvements_stock (voir migration 0006).
   Ajout additif : ne modifie aucune fonction existante d'index.html.
   ========================================================================== */

function waitForBridge() {
  return new Promise((resolve) => {
    if (window.OKITAKU_BRIDGE) return resolve(window.OKITAKU_BRIDGE);
    const t = setInterval(() => {
      if (window.OKITAKU_BRIDGE) { clearInterval(t); resolve(window.OKITAKU_BRIDGE); }
    }, 30);
  });
}

const B = await waitForBridge();
const { sb, fmt, todayStr, escapeHtml, attachJustificatifLinks } = B;

const TYPE_LABELS = {
  vente: 'Vente', pret: 'Prêt', campagne: 'Campagne', cadeau: 'Cadeau',
  consommation_interne: 'Consommation interne', perte: 'Perte', casse: 'Produit cassé',
  retour_fournisseur: 'Retour fournisseur', echantillon: 'Échantillon'
};

let HS_ALL = [];

async function fetchSorties() {
  const { data, error } = await sb.from('v_sorties_stock').select('*').order('created_at', { ascending: false }).limit(2000);
  if (error) { console.error(error); alert('Erreur de chargement du registre des sorties : ' + error.message); return []; }
  return data || [];
}

function applyFiltersAndRender() {
  const q = (document.getElementById('hs-search').value || '').trim().toLowerCase();
  const df = document.getElementById('hs-filter-date-debut').value;
  const dt = document.getElementById('hs-filter-date-fin').value;
  const type = document.getElementById('hs-filter-type').value;

  const filtered = HS_ALL.filter(m => {
    if (type && m.type_sortie !== type) return false;
    if (df && m.date < df) return false;
    if (dt && m.date > dt) return false;
    if (q) {
      const hay = [m.article_code, m.article_libelle, m.personne_concernee, m.telephone, m.motif, m.numero_auto].join(' ').toLowerCase();
      if (!hay.includes(q)) return false;
    }
    return true;
  });
  renderTable(filtered);
  return filtered;
}

function renderTable(list) {
  const tbody = document.querySelector('#tbl-sorties-stock tbody');
  tbody.innerHTML = list.map(m => `
    <tr>
      <td>${escapeHtml(m.numero_auto || '—')}</td>
      <td>${escapeHtml(m.date)}</td>
      <td>${escapeHtml(m.heure || '—')}</td>
      <td>${escapeHtml(m.article_code)} — ${escapeHtml(m.article_libelle)}</td>
      <td class="num">${m.quantite}</td>
      <td class="num">${fmt(m.prix_unitaire)}</td>
      <td class="num">${fmt(m.valeur_totale)}</td>
      <td>${escapeHtml(m.personne_concernee || '—')}</td>
      <td>${escapeHtml(m.telephone || '—')}</td>
      <td><span class="pill info">${escapeHtml(TYPE_LABELS[m.type_sortie] || m.type_sortie || '—')}</span></td>
      <td>${escapeHtml(m.motif || '—')}</td>
      <td>${escapeHtml(m.utilisateur || '—')}</td>
      <td>${m.justificatif_path ? `<a href="#" target="_blank" data-justificatif="${escapeHtml(m.justificatif_path)}">📎 Voir</a>` : '—'}</td>
    </tr>`).join('') || '<tr><td colspan="13" style="color:var(--text-muted)">Aucune sortie enregistrée pour le moment.</td></tr>';
  attachJustificatifLinks(document.querySelector('#tbl-sorties-stock'));
}

document.getElementById('hs-btn-reset-filtres').addEventListener('click', () => {
  document.getElementById('hs-search').value = '';
  document.getElementById('hs-filter-date-debut').value = '';
  document.getElementById('hs-filter-date-fin').value = '';
  document.getElementById('hs-filter-type').value = '';
  applyFiltersAndRender();
});
['hs-search', 'hs-filter-date-debut', 'hs-filter-date-fin', 'hs-filter-type'].forEach(id => {
  document.getElementById(id).addEventListener('input', applyFiltersAndRender);
  document.getElementById(id).addEventListener('change', applyFiltersAndRender);
});

document.getElementById('hs-btn-export-excel').addEventListener('click', () => {
  if (!window.XLSX) return alert("La librairie d'export Excel n'a pas pu être chargée (connexion internet ?).");
  const list = applyFiltersAndRender();
  const rows = list.map(m => ({
    'N°': m.numero_auto, Date: m.date, Heure: m.heure, Produit: `${m.article_code} — ${m.article_libelle}`,
    'Quantité': m.quantite, 'Prix unitaire (FCFA)': m.prix_unitaire, 'Valeur totale (FCFA)': m.valeur_totale,
    'Personne': m.personne_concernee || '', 'Téléphone': m.telephone || '',
    'Type': TYPE_LABELS[m.type_sortie] || m.type_sortie || '', 'Motif': m.motif || '', 'Utilisateur': m.utilisateur || ''
  }));
  const ws = window.XLSX.utils.json_to_sheet(rows);
  const wb = window.XLSX.utils.book_new();
  window.XLSX.utils.book_append_sheet(wb, ws, 'Sorties de stock');
  window.XLSX.writeFile(wb, `historique_sorties_${todayStr()}.xlsx`);
});

document.getElementById('hs-btn-print').addEventListener('click', () => {
  const list = applyFiltersAndRender();
  const rowsHtml = list.map(m => `
    <tr>
      <td>${escapeHtml(m.numero_auto || '')}</td><td>${escapeHtml(m.date)}</td><td>${escapeHtml(m.heure||'')}</td>
      <td>${escapeHtml(m.article_code)} — ${escapeHtml(m.article_libelle)}</td>
      <td style="text-align:right;">${m.quantite}</td><td style="text-align:right;">${fmt(m.valeur_totale)}</td>
      <td>${escapeHtml(m.personne_concernee||'')}</td><td>${escapeHtml(TYPE_LABELS[m.type_sortie]||m.type_sortie||'')}</td>
      <td>${escapeHtml(m.motif||'')}</td><td>${escapeHtml(m.utilisateur||'')}</td>
    </tr>`).join('');
  const html = `<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Historique des sorties de stock</title>
  <style>body{font-family:system-ui,sans-serif;padding:20px;} table{width:100%;border-collapse:collapse;} th,td{border-bottom:1px solid #ddd;padding:5px 7px;font-size:11px;text-align:left;} th{background:#f5f5f4;}</style>
  </head><body><h2>Historique des sorties de stock — Okitaku Shop</h2><p>Édité le ${new Date().toLocaleString('fr-FR')}</p>
  <table><thead><tr><th>N°</th><th>Date</th><th>Heure</th><th>Produit</th><th>Qté</th><th>Valeur</th><th>Personne</th><th>Type</th><th>Motif</th><th>Utilisateur</th></tr></thead>
  <tbody>${rowsHtml}</tbody></table>
  <script>window.onload = () => window.print();<\/script></body></html>`;
  const w = window.open('', '_blank');
  if (!w) return alert('Le navigateur a bloqué la fenêtre d\'impression (pop-up). Autorise les pop-ups pour ce site.');
  w.document.write(html);
  w.document.close();
});

async function refresh() {
  HS_ALL = await fetchSorties();
  applyFiltersAndRender();
}

window.OKITAKU_HS = { refresh };
