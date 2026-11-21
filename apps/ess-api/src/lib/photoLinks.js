'use strict';

/**
 * Photo links for the people in a reply (#141; team_app #139 B2, Prakash 21 Nov 2026: one profile photo everywhere).
 *
 * The lists (My Team, the org tree and directory, the Wall, Celebrations, leaders) used to carry no photo, so the app
 * drew initials. `withPhotoLinks(store, body)` finds every person card in a reply (an object with a uuid `id` and a
 * `full_name`), reads their HR photo in ONE query and signs the photos in ONE call, and adds to each card:
 *   photo_url          a 5-minute signed link to hr_employees.photo_path (the photo HR, the Team app and the web
 *                      Profile page set), or null; the stored path never leaves the server
 *   photo_updated_at   when it last changed, so the app can cache by person and time
 * A photo is never a reason to fail a list: any read or signing failure leaves photo_url null.
 */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_DEPTH = 12;

function collectCards(node, out, depth = 0) {
  if (!node || typeof node !== 'object' || depth > MAX_DEPTH) return;
  if (Array.isArray(node)) {
    for (const item of node) collectCards(item, out, depth + 1);
    return;
  }
  if (typeof node.id === 'string' && UUID.test(node.id) && typeof node.full_name === 'string') out.push(node);
  for (const value of Object.values(node)) {
    if (value && typeof value === 'object') collectCards(value, out, depth + 1);
  }
}

async function withPhotoLinks(store, body) {
  const cards = [];
  collectCards(body, cards);
  if (!cards.length) return body;
  const ids = [...new Set(cards.map((c) => c.id.toLowerCase()))];
  let byId = new Map();
  try {
    const rows = typeof store.employeePhotos === 'function' ? await store.employeePhotos(ids) : [];
    const paths = [...new Set(rows.map((r) => r.photo_path).filter(Boolean))];
    const urls = paths.length && typeof store.signedPhotoUrls === 'function' ? await store.signedPhotoUrls(paths) : new Map();
    byId = new Map(rows.map((r) => [String(r.id).toLowerCase(), {
      photo_url: (r.photo_path && urls.get(r.photo_path)) || null,
      photo_updated_at: r.photo_updated_at || null,
    }]));
  } catch {
    byId = new Map();
  }
  for (const card of cards) {
    const found = byId.get(card.id.toLowerCase());
    card.photo_url = found ? found.photo_url : null;
    card.photo_updated_at = found ? found.photo_updated_at : null;
  }
  return body;
}

module.exports = { withPhotoLinks, collectCards };
