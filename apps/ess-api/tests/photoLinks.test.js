'use strict';

const { withPhotoLinks, collectCards } = require('../src/lib/photoLinks');

/**
 * #141: every person card in a list reply gets photo_url and photo_updated_at, read in one query and signed in one
 * call; no photo, a failed read or a failed signing all give null and never fail the reply.
 */
const A = 'aaaaaaaa-0000-4000-8000-000000000001';
const B = 'bbbbbbbb-0000-4000-8000-000000000002';
const C = 'cccccccc-0000-4000-8000-000000000003';

function storeWith(rows, { failRead = false, failSign = false } = {}) {
  const calls = { read: 0, sign: 0, ids: null, paths: null };
  return {
    calls,
    employeePhotos: async (ids) => {
      calls.read += 1;
      calls.ids = ids;
      if (failRead) throw new Error('read failed');
      return rows.filter((r) => ids.includes(r.id));
    },
    signedPhotoUrls: async (paths) => {
      calls.sign += 1;
      calls.paths = paths;
      if (failSign) throw new Error('sign failed');
      return new Map(paths.map((p) => [p, `https://signed.test/${p}`]));
    },
  };
}

const body = () => ({
  manager_chain: [{ id: A, full_name: 'Alpha' }],
  peers: [{ id: B, full_name: 'Beta', branch: { id: C, name: 'A branch, not a person' } }],
  tree: { id: C, full_name: 'Gamma', children: [{ id: A, full_name: 'Alpha again' }] },
});

describe('withPhotoLinks (#141)', () => {
  it('finds every person card, nested or repeated, and nothing that has no full_name', () => {
    const out = [];
    collectCards(body(), out);
    expect(out.map((c) => c.full_name)).toEqual(['Alpha', 'Beta', 'Gamma', 'Alpha again']);
  });

  it('one read and one signing call for the whole reply; a person with no photo gets null', async () => {
    const store = storeWith([{ id: A, photo_path: 'hr/employee/a/photo/a.jpg', photo_updated_at: '2026-11-21T10:00:00Z' }]);
    const out = await withPhotoLinks(store, body());
    expect([store.calls.read, store.calls.sign]).toEqual([1, 1]);
    expect(store.calls.ids.sort()).toEqual([A, B, C].sort());
    expect(store.calls.paths).toEqual(['hr/employee/a/photo/a.jpg']);
    expect(out.manager_chain[0]).toMatchObject({ photo_url: 'https://signed.test/hr/employee/a/photo/a.jpg', photo_updated_at: '2026-11-21T10:00:00Z' });
    expect(out.tree.children[0].photo_url).toBe('https://signed.test/hr/employee/a/photo/a.jpg');
    expect(out.peers[0]).toMatchObject({ photo_url: null, photo_updated_at: null });
    expect(out.peers[0].branch).not.toHaveProperty('photo_url');
    expect(JSON.stringify(out)).not.toContain('photo_path');
  });

  it('a failed read or signing leaves every photo null and the reply whole', async () => {
    for (const opts of [{ failRead: true }, { failSign: true }]) {
      const out = await withPhotoLinks(storeWith([{ id: A, photo_path: 'p.jpg', photo_updated_at: null }], opts), body());
      expect(out.manager_chain[0].full_name).toBe('Alpha');
      expect(out.manager_chain[0].photo_url).toBeNull();
    }
  });

  it('no signing call when nobody has a photo, and a reply with no people is returned untouched', async () => {
    const store = storeWith([]);
    await withPhotoLinks(store, body());
    expect([store.calls.read, store.calls.sign]).toEqual([1, 0]);
    const empty = { week: { from: '2026-11-16', to: '2026-11-22' }, people: [] };
    expect(await withPhotoLinks(store, empty)).toEqual({ week: { from: '2026-11-16', to: '2026-11-22' }, people: [] });
  });
});
