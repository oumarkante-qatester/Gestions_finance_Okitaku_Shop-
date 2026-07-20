/* ==========================================================================
   PRETS DE PRODUITS — module autonome (ES module)
   Ajout additif : ne modifie aucune fonction existante d'index.html.
   Dépend de window.OKITAKU_BRIDGE (voir la fin du <script> principal).
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
const { sb, fmt, todayStr, escapeHtml } = B;

let PP_ALL = [];          // tous les prêts non supprimés, avec leurs lignes
let PP_ARTICLES = [];     // cache articles pour les pickers (rafraîchi à chaque ouverture de dialogue)
let PP_CURRENT_LINES = []; // lignes en cours d'édition dans la boîte de dialogue create/edit
let PP_EDITING_LOCKED = false; // true si des retours existent déjà (produits non modifiables)

function statutBadge(p) {
  const today = todayStr();
  if (p.statut === 'retourne') return '<span class="pill ok">Retourné</span>';
  if (p.statut === 'annule') return '<span class="pill no">Annulé</span>';
  if (p.date_retour_prevue && p.date_retour_prevue < today) return '<span class="pill warn">En retard</span>';
  return '<span class="pill info">En cours</span>';
}

function ligneRestante(l) { return Number(l.quantite) - Number(l.quantite_retournee || 0); }

function valeurRestante(p) {
  return (p.lignes || []).reduce((s, l) => s + ligneRestante(l) * Number(l.prix_unitaire || 0), 0);
}

function produitsSummary(p) {
  return (p.lignes || []).map(l => `${escapeHtml(l.articles ? l.articles.code : '?')} × ${l.quantite}`).join(', ') || '—';
}

async function fetchPrets() {
  const { data, error } = await sb
    .from('prets_produits')
    .select('*, lignes:prets_produits_lignes(id, article_id, quantite, prix_unitaire, quantite_retournee, articles(code, libelle))')
    .is('deleted_at', null)
    .order('created_at', { ascending: false });
  if (error) { console.error(error); alert('Erreur de chargement des prêts : ' + error.message); return []; }
  return data || [];
}

async function fetchArticlesForPicker() {
  const { data, error } = await sb.from('v_articles_stock').select('id,code,libelle,prix_vente,stock_restant').order('code');
  if (error) { console.error(error); return []; }
  return data || [];
}

function applyFiltersAndRender() {
  const q = (document.getElementById('pp-search').value || '').trim().toLowerCase();
  const df = document.getElementById('pp-filter-date-debut').value;
  const dt = document.getElementById('pp-filter-date-fin').value;
  const statut = document.getElementById('pp-filter-statut').value;

  const filtered = PP_ALL.filter(p => {
    if (statut && p.statut !== statut) return false;
    if (df && p.date < df) return false;
    if (dt && p.date > dt) return false;
    if (q) {
      const hay = [
        p.numero, p.nom_beneficiaire, p.telephone, p.observation,
        ...(p.lignes || []).map(l => l.articles ? `${l.articles.code} ${l.articles.libelle}` : '')
      ].join(' ').toLowerCase();
      if (!hay.includes(q)) return false;
    }
    return true;
  });

  renderTable(filtered);
  renderKPIs(PP_ALL); // les KPI restent globaux, indépendants des filtres d'affichage
  return filtered;
}

function renderTable(list) {
  const tbody = document.querySelector('#tbl-pret-produits tbody');
  tbody.innerHTML = list.map(p => `
    <tr>
      <td>${escapeHtml(p.numero || '—')}</td>
      <td>${escapeHtml(p.date)}</td>
      <td>${escapeHtml(p.nom_beneficiaire)}</td>
      <td>${escapeHtml(p.telephone || '—')}</td>
      <td>${produitsSummary(p)}</td>
      <td class="num">${fmt(p.valeur_totale)}</td>
      <td>${p.date_retour_prevue ? escapeHtml(p.date_retour_prevue) : '—'}</td>
      <td>${p.date_retour_reelle ? escapeHtml(p.date_retour_reelle) : '—'}</td>
      <td>${statutBadge(p)}</td>
      <td style="white-space:nowrap;">
        ${p.statut === 'en_cours' ? `<button class="btn btn-sm" data-pp-retour="${p.id}">Retour</button>` : ''}
        <button class="btn btn-sm" data-pp-edit="${p.id}">✏️</button>
        <button class="btn btn-sm" data-pp-print="${p.id}">🖨️</button>
        <button class="btn btn-sm btn-danger" data-pp-del="${p.id}">🗑️</button>
      </td>
    </tr>`).join('') || '<tr><td colspan="10" style="color:var(--text-muted)">Aucun prêt de produits pour le moment.</td></tr>';

  tbody.querySelectorAll('button[data-pp-retour]').forEach(b => b.addEventListener('click', () => openRetourDialog(b.dataset.ppRetour)));
  tbody.querySelectorAll('button[data-pp-edit]').forEach(b => b.addEventListener('click', () => openEditDialog(b.dataset.ppEdit)));
  tbody.querySelectorAll('button[data-pp-print]').forEach(b => b.addEventListener('click', () => printBonDePret(b.dataset.ppPrint)));
  tbody.querySelectorAll('button[data-pp-del]').forEach(b => b.addEventListener('click', () => deletePret(b.dataset.ppDel)));
}

function renderKPIs(all) {
  const today = todayStr();
  const enCours = all.filter(p => p.statut === 'en_cours');
  const retard = enCours.filter(p => p.date_retour_prevue && p.date_retour_prevue < today);
  const retournes = all.filter(p => p.statut === 'retourne').length;
  const valeur = enCours.reduce((s, p) => s + valeurRestante(p), 0);
  document.getElementById('pp-kpi-encours').textContent = String(enCours.length);
  document.getElementById('pp-kpi-valeur').textContent = fmt(valeur);
  document.getElementById('pp-kpi-retard').textContent = String(retard.length);
  document.getElementById('pp-kpi-retournes').textContent = String(retournes);
}

/* ---------- DIALOGUE CREATE / EDIT ---------- */

function renderLignesRows() {
  const tbody = document.getElementById('pp-lignes-body');
  tbody.innerHTML = PP_CURRENT_LINES.map((l, idx) => `
    <tr data-idx="${idx}">
      <td>
        <select data-role="article" ${PP_EDITING_LOCKED ? 'disabled' : ''} style="min-width:200px;">
          <option value="">— Choisir —</option>
          ${PP_ARTICLES.map(a => `<option value="${a.id}" ${a.id === l.article_id ? 'selected' : ''}>${escapeHtml(a.code)} — ${escapeHtml(a.libelle)} (stock: ${a.stock_restant})</option>`).join('')}
        </select>
      </td>
      <td><input data-role="qte" type="number" min="1" value="${l.quantite || ''}" style="width:70px;" ${PP_EDITING_LOCKED ? 'disabled' : ''} /></td>
      <td><input data-role="prix" type="number" min="0" value="${l.prix_unitaire || 0}" style="width:90px;" ${PP_EDITING_LOCKED ? 'disabled' : ''} /></td>
      <td class="num">${fmt((Number(l.quantite) || 0) * (Number(l.prix_unitaire) || 0))}</td>
      <td>${PP_EDITING_LOCKED ? '' : '<button class="btn btn-sm btn-danger" data-role="del">✕</button>'}</td>
    </tr>`).join('') || '<tr><td colspan="5" style="color:var(--text-muted)">Aucun produit ajouté.</td></tr>';

  tbody.querySelectorAll('tr').forEach(tr => {
    const idx = Number(tr.dataset.idx);
    const selArticle = tr.querySelector('[data-role="article"]');
    const inQte = tr.querySelector('[data-role="qte"]');
    const inPrix = tr.querySelector('[data-role="prix"]');
    const btnDel = tr.querySelector('[data-role="del"]');
    if (selArticle) selArticle.addEventListener('change', () => {
      PP_CURRENT_LINES[idx].article_id = selArticle.value;
      const art = PP_ARTICLES.find(a => a.id === selArticle.value);
      if (art && !PP_CURRENT_LINES[idx].prix_unitaire) {
        PP_CURRENT_LINES[idx].prix_unitaire = art.prix_vente || 0;
        renderLignesRows();
        updateTotal();
      }
    });
    if (inQte) inQte.addEventListener('input', () => { PP_CURRENT_LINES[idx].quantite = Number(inQte.value); updateTotal(); tr.children[3].textContent = fmt((Number(inQte.value)||0) * (Number(inPrix.value)||0)); });
    if (inPrix) inPrix.addEventListener('input', () => { PP_CURRENT_LINES[idx].prix_unitaire = Number(inPrix.value); updateTotal(); tr.children[3].textContent = fmt((Number(inQte.value)||0) * (Number(inPrix.value)||0)); });
    if (btnDel) btnDel.addEventListener('click', () => { PP_CURRENT_LINES.splice(idx, 1); renderLignesRows(); updateTotal(); });
  });
}

function updateTotal() {
  const total = PP_CURRENT_LINES.reduce((s, l) => s + (Number(l.quantite) || 0) * (Number(l.prix_unitaire) || 0), 0);
  document.getElementById('pp-total').textContent = fmt(total);
}

document.getElementById('pp-btn-add-ligne').addEventListener('click', () => {
  if (PP_EDITING_LOCKED) return;
  PP_CURRENT_LINES.push({ article_id: '', quantite: 1, prix_unitaire: 0 });
  renderLignesRows();
});

async function openCreateDialog() {
  PP_ARTICLES = await fetchArticlesForPicker();
  PP_CURRENT_LINES = [];
  PP_EDITING_LOCKED = false;
  document.getElementById('pp-dlg-title').textContent = 'Nouveau prêt de produits';
  document.getElementById('pp-id').value = '';
  document.getElementById('pp-nom').value = '';
  document.getElementById('pp-tel').value = '';
  document.getElementById('pp-adresse').value = '';
  document.getElementById('pp-observation').value = '';
  document.getElementById('pp-date').value = todayStr();
  document.getElementById('pp-date-retour-prevue').value = '';
  document.getElementById('pp-lignes-lock-msg').style.display = 'none';
  renderLignesRows();
  updateTotal();
  document.getElementById('dlg-pp').showModal();
}

async function openEditDialog(id) {
  const p = PP_ALL.find(x => x.id === id);
  if (!p) return;
  PP_ARTICLES = await fetchArticlesForPicker();
  PP_EDITING_LOCKED = (p.lignes || []).some(l => Number(l.quantite_retournee || 0) > 0);
  PP_CURRENT_LINES = (p.lignes || []).map(l => ({ id: l.id, article_id: l.article_id, quantite: l.quantite, prix_unitaire: l.prix_unitaire }));
  document.getElementById('pp-dlg-title').textContent = 'Modifier — ' + (p.numero || '');
  document.getElementById('pp-id').value = p.id;
  document.getElementById('pp-nom').value = p.nom_beneficiaire || '';
  document.getElementById('pp-tel').value = p.telephone || '';
  document.getElementById('pp-adresse').value = p.adresse || '';
  document.getElementById('pp-observation').value = p.observation || '';
  document.getElementById('pp-date').value = p.date || todayStr();
  document.getElementById('pp-date-retour-prevue').value = p.date_retour_prevue || '';
  document.getElementById('pp-lignes-lock-msg').style.display = PP_EDITING_LOCKED ? 'block' : 'none';
  document.getElementById('pp-btn-add-ligne').style.display = PP_EDITING_LOCKED ? 'none' : '';
  renderLignesRows();
  updateTotal();
  document.getElementById('dlg-pp').showModal();
}

document.getElementById('pp-btn-new').addEventListener('click', openCreateDialog);
document.getElementById('pp-cancel').addEventListener('click', () => document.getElementById('dlg-pp').close());

document.getElementById('pp-confirm').addEventListener('click', async () => {
  const id = document.getElementById('pp-id').value;
  const nom = document.getElementById('pp-nom').value.trim();
  const tel = document.getElementById('pp-tel').value.trim() || null;
  const adresse = document.getElementById('pp-adresse').value.trim() || null;
  const observation = document.getElementById('pp-observation').value.trim() || null;
  const date = document.getElementById('pp-date').value || todayStr();
  const dateRetourPrevue = document.getElementById('pp-date-retour-prevue').value || null;

  if (!nom) return alert('Le nom du bénéficiaire est requis.');
  const lignesValides = PP_CURRENT_LINES.filter(l => l.article_id && Number(l.quantite) > 0);
  if (!PP_EDITING_LOCKED && lignesValides.length === 0) return alert('Ajoute au moins un produit prêté.');

  const btn = document.getElementById('pp-confirm');
  btn.disabled = true; btn.textContent = 'Enregistrement…';

  try {
    if (!id) {
      const { error } = await sb.rpc('creer_pret_produits', {
        p_nom_beneficiaire: nom, p_telephone: tel, p_adresse: adresse, p_observation: observation,
        p_date: date, p_date_retour_prevue: dateRetourPrevue,
        p_lignes: lignesValides.map(l => ({ article_id: l.article_id, quantite: Number(l.quantite), prix_unitaire: Number(l.prix_unitaire) || 0 }))
      });
      if (error) throw error;
    } else {
      const { error: e1 } = await sb.from('prets_produits').update({
        nom_beneficiaire: nom, telephone: tel, adresse, observation, date, date_retour_prevue: dateRetourPrevue
      }).eq('id', id);
      if (e1) throw e1;
      if (!PP_EDITING_LOCKED) {
        const { error: e2 } = await sb.rpc('modifier_lignes_pret_produits', {
          p_pret_id: id,
          p_lignes: lignesValides.map(l => ({ article_id: l.article_id, quantite: Number(l.quantite), prix_unitaire: Number(l.prix_unitaire) || 0 }))
        });
        if (e2) throw e2;
      }
    }
    document.getElementById('dlg-pp').close();
    await refresh();
  } catch (e) {
    alert('Erreur : ' + (e.message || e));
  } finally {
    btn.disabled = false; btn.textContent = 'Enregistrer';
  }
});

/* ---------- DIALOGUE RETOUR ---------- */

async function openRetourDialog(id) {
  const p = PP_ALL.find(x => x.id === id);
  if (!p) return;
  document.getElementById('pp-retour-title').textContent = 'Retour — ' + (p.numero || '');
  document.getElementById('pp-retour-pret-id').value = p.id;
  document.getElementById('pp-retour-desc').textContent = `${p.nom_beneficiaire}${p.telephone ? ' · ' + p.telephone : ''}`;
  document.getElementById('pp-retour-note').value = '';
  document.querySelector('#pp-retour-lignes-body').innerHTML = (p.lignes || []).map(l => {
    const restant = ligneRestante(l);
    return `<tr data-ligne-id="${l.id}" data-restant="${restant}">
      <td>${escapeHtml(l.articles ? `${l.articles.code} — ${l.articles.libelle}` : '?')}</td>
      <td class="num">${l.quantite}</td>
      <td class="num">${l.quantite_retournee || 0}</td>
      <td class="num">${restant}</td>
      <td class="num"><input type="number" min="0" max="${restant}" value="0" style="width:70px;" ${restant <= 0 ? 'disabled' : ''} /></td>
    </tr>`;
  }).join('');
  document.getElementById('dlg-pp-retour').showModal();
}

document.getElementById('pp-retour-cancel').addEventListener('click', () => document.getElementById('dlg-pp-retour').close());

document.getElementById('pp-retour-confirm').addEventListener('click', async () => {
  const note = document.getElementById('pp-retour-note').value.trim() || null;
  const rows = [...document.querySelectorAll('#pp-retour-lignes-body tr')];
  const btn = document.getElementById('pp-retour-confirm');
  btn.disabled = true; btn.textContent = 'Enregistrement…';
  try {
    for (const tr of rows) {
      const ligneId = tr.dataset.ligneId;
      const input = tr.querySelector('input');
      const qte = Number(input.value || 0);
      if (qte > 0) {
        const { error } = await sb.rpc('retourner_ligne_pret_produits', { p_ligne_id: ligneId, p_quantite: qte, p_note: note });
        if (error) throw error;
      }
    }
    document.getElementById('dlg-pp-retour').close();
    await refresh();
  } catch (e) {
    alert('Erreur : ' + (e.message || e));
  } finally {
    btn.disabled = false; btn.textContent = 'Enregistrer le retour';
  }
});

document.getElementById('pp-retour-annuler').addEventListener('click', async () => {
  const id = document.getElementById('pp-retour-pret-id').value;
  if (!confirm("Annuler ce prêt ? Le stock restant dû sera automatiquement restitué.")) return;
  const { error } = await sb.rpc('annuler_pret_produits', { p_pret_id: id });
  if (error) return alert('Erreur : ' + error.message);
  document.getElementById('dlg-pp-retour').close();
  await refresh();
});

/* ---------- SUPPRESSION (corbeille) ---------- */

async function deletePret(id) {
  if (!confirm("Supprimer ce prêt ? Il sera archivé (corbeille) et le stock restant dû sera restitué automatiquement.")) return;
  const { error } = await sb.rpc('supprimer_pret_produits', { p_pret_id: id });
  if (error) return alert('Erreur : ' + error.message);
  await refresh();
}

/* ---------- IMPRESSION / EXPORT ---------- */

function printBonDePret(id) {
  const p = PP_ALL.find(x => x.id === id);
  if (!p) return;
  const lignesHtml = (p.lignes || []).map(l => `
    <tr>
      <td>${escapeHtml(l.articles ? `${l.articles.code} — ${l.articles.libelle}` : '?')}</td>
      <td style="text-align:right;">${l.quantite}</td>
      <td style="text-align:right;">${fmt(l.prix_unitaire)}</td>
      <td style="text-align:right;">${fmt(l.quantite * l.prix_unitaire)}</td>
    </tr>`).join('');
  const html = `<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Bon de prêt ${escapeHtml(p.numero||'')}</title>
  <style>
    body{font-family:system-ui,sans-serif;padding:24px;color:#111;}
    h1{font-size:18px;margin:0 0 4px;} .sub{color:#555;font-size:12px;margin-bottom:18px;}
    table{width:100%;border-collapse:collapse;margin-top:12px;} th,td{padding:6px 8px;border-bottom:1px solid #ddd;font-size:13px;}
    th{text-align:left;background:#f5f5f4;} .tot{font-weight:700;}
    .meta div{margin-bottom:4px;font-size:13px;} .sign{margin-top:60px;display:flex;justify-content:space-between;font-size:12px;}
    .sign div{width:45%;border-top:1px solid #999;padding-top:6px;}
  </style></head><body>
    <h1>Bon de prêt ${escapeHtml(p.numero || '')}</h1>
    <div class="sub">Okitaku Shop — édité le ${new Date().toLocaleString('fr-FR')}</div>
    <div class="meta">
      <div><b>Bénéficiaire :</b> ${escapeHtml(p.nom_beneficiaire)}</div>
      <div><b>Téléphone :</b> ${escapeHtml(p.telephone || '—')}</div>
      <div><b>Adresse :</b> ${escapeHtml(p.adresse || '—')}</div>
      <div><b>Date du prêt :</b> ${escapeHtml(p.date)}</div>
      <div><b>Retour prévu :</b> ${escapeHtml(p.date_retour_prevue || '—')}</div>
      <div><b>Observation :</b> ${escapeHtml(p.observation || '—')}</div>
    </div>
    <table><thead><tr><th>Produit</th><th style="text-align:right;">Qté</th><th style="text-align:right;">Prix unit.</th><th style="text-align:right;">Total</th></tr></thead>
    <tbody>${lignesHtml}</tbody>
    <tfoot><tr class="tot"><td colspan="3" style="text-align:right;">Total</td><td style="text-align:right;">${fmt(p.valeur_totale)}</td></tr></tfoot></table>
    <div class="sign"><div>Signature (boutique)</div><div>Signature (bénéficiaire)</div></div>
    <script>window.onload = () => window.print();</script>
  </body></html>`;
  const w = window.open('', '_blank');
  if (!w) return alert('Le navigateur a bloqué la fenêtre d\'impression (pop-up). Autorise les pop-ups pour ce site.');
  w.document.write(html);
  w.document.close();
}

document.getElementById('pp-btn-print').addEventListener('click', () => {
  const list = applyFiltersAndRender();
  const rowsHtml = list.map(p => `
    <tr>
      <td>${escapeHtml(p.numero || '')}</td><td>${escapeHtml(p.date)}</td><td>${escapeHtml(p.nom_beneficiaire)}</td>
      <td>${escapeHtml(p.telephone || '')}</td><td>${produitsSummary(p)}</td>
      <td style="text-align:right;">${fmt(p.valeur_totale)}</td>
      <td>${escapeHtml(p.date_retour_prevue || '')}</td><td>${escapeHtml(p.date_retour_reelle || '')}</td>
      <td>${p.statut}</td>
    </tr>`).join('');
  const html = `<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Prêts de produits</title>
  <style>body{font-family:system-ui,sans-serif;padding:20px;} table{width:100%;border-collapse:collapse;} th,td{border-bottom:1px solid #ddd;padding:5px 7px;font-size:12px;text-align:left;} th{background:#f5f5f4;}</style>
  </head><body><h2>Prêts de produits — Okitaku Shop</h2><p>Édité le ${new Date().toLocaleString('fr-FR')}</p>
  <table><thead><tr><th>N°</th><th>Date</th><th>Bénéficiaire</th><th>Téléphone</th><th>Produits</th><th>Valeur totale</th><th>Retour prévu</th><th>Retour réel</th><th>Statut</th></tr></thead>
  <tbody>${rowsHtml}</tbody></table>
  <script>window.onload = () => window.print();<\/script></body></html>`;
  const w = window.open('', '_blank');
  if (!w) return alert('Le navigateur a bloqué la fenêtre d\'impression (pop-up). Autorise les pop-ups pour ce site.');
  w.document.write(html);
  w.document.close();
});

document.getElementById('pp-btn-export-excel').addEventListener('click', () => {
  if (!window.XLSX) return alert("La librairie d'export Excel n'a pas pu être chargée (connexion internet ?).");
  const list = applyFiltersAndRender();
  const rows = list.map(p => ({
    'N°': p.numero, Date: p.date, 'Bénéficiaire': p.nom_beneficiaire, 'Téléphone': p.telephone || '',
    'Adresse': p.adresse || '', 'Produits': produitsSummary(p).replace(/<[^>]+>/g, ''),
    'Valeur totale (FCFA)': p.valeur_totale, 'Retour prévu': p.date_retour_prevue || '',
    'Retour réel': p.date_retour_reelle || '', 'Statut': p.statut, 'Observation': p.observation || ''
  }));
  const ws = window.XLSX.utils.json_to_sheet(rows);
  const wb = window.XLSX.utils.book_new();
  window.XLSX.utils.book_append_sheet(wb, ws, 'Prêts de produits');
  window.XLSX.writeFile(wb, `prets_produits_${todayStr()}.xlsx`);
});

document.getElementById('pp-btn-reset-filtres').addEventListener('click', () => {
  document.getElementById('pp-search').value = '';
  document.getElementById('pp-filter-date-debut').value = '';
  document.getElementById('pp-filter-date-fin').value = '';
  document.getElementById('pp-filter-statut').value = '';
  applyFiltersAndRender();
});
['pp-search', 'pp-filter-date-debut', 'pp-filter-date-fin', 'pp-filter-statut'].forEach(id => {
  document.getElementById(id).addEventListener('input', applyFiltersAndRender);
  document.getElementById(id).addEventListener('change', applyFiltersAndRender);
});

/* ---------- ENTREE PRINCIPALE ---------- */

async function refresh() {
  PP_ALL = await fetchPrets();
  applyFiltersAndRender();
}

window.OKITAKU_PP = { refresh };
