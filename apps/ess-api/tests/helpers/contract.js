const fs = require('fs');
const path = require('path');
const YAML = require('yaml');
const Ajv2020 = require('ajv/dist/2020');

/**
 * packages/contracts/openapi.yaml, the one contract the app is built against (ADR-0010), turned
 * into checks the tests run against the ESS's real replies (tests/contract.test.js).
 *
 * OpenAPI schemas leave objects open to fields they do not name. Here every object schema that
 * names its properties is closed, so a reply carrying a field the contract does not document
 * fails, just as a reply missing a required one does: the app may only rely on what is written.
 */

// ESS_CONTRACT_FILE checks the replies against a draft before it is copied into
// packages/contracts; CI never sets it.
const CONTRACT_FILE = process.env.ESS_CONTRACT_FILE
  || path.join(__dirname, '..', '..', '..', '..', 'packages', 'contracts', 'openapi.yaml');
const contract = YAML.parse(fs.readFileSync(CONTRACT_FILE, 'utf8'));

const METHODS = ['get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace'];
const SCHEMAS_ID = 'contract-schemas';

/** Follows a local $ref ('#/components/responses/EssForbidden') to what it names. */
function deref(node) {
  let out = node;
  const seen = [];
  while (out && typeof out.$ref === 'string') {
    const ref = out.$ref;
    if (!ref.startsWith('#/') || seen.includes(ref)) throw new Error(`cannot follow $ref ${ref}`);
    seen.push(ref);
    out = ref.slice(2).split('/')
      .map((key) => key.replace(/~1/g, '/').replace(/~0/g, '~'))
      .reduce((n, key) => (n == null ? n : n[key]), contract);
    if (out == null) throw new Error(`the contract has nothing at ${ref}`);
  }
  return out;
}

/** Keys whose values are data or names, never schemas, and so are copied as they are. */
const DATA_KEYS = new Set(['enum', 'const', 'default', 'examples', 'example', 'required']);

/** An OpenAPI 3.1 schema as plain JSON Schema 2020-12, closed against undocumented fields. */
function toJsonSchema(node) {
  if (Array.isArray(node)) return node.map(toJsonSchema);
  if (!node || typeof node !== 'object') return node;
  const out = {};
  for (const [key, value] of Object.entries(node)) {
    if (key.startsWith('x-')) continue;
    if (key === '$ref') out.$ref = String(value).replace('#/components/schemas/', `${SCHEMAS_ID}#/$defs/`);
    else if (DATA_KEYS.has(key)) out[key] = value;
    else if (key === 'properties') out.properties = Object.fromEntries(Object.entries(value).map(([name, s]) => [name, toJsonSchema(s)]));
    else out[key] = toJsonSchema(value);
  }
  if (out.properties && out.additionalProperties === undefined) out.additionalProperties = false;
  return out;
}

const ajv = new Ajv2020({ allErrors: true, allowUnionTypes: true, strict: true });
// The three formats the contract uses. A new one fails loudly ("unknown format") until it is added.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
ajv.addFormat('uuid', UUID_RE);
ajv.addFormat('date', (s) => {
  const day = new Date(`${s}T00:00:00Z`);
  // A real calendar day only: 2026-02-30 is not one.
  return /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(day.getTime()) && day.toISOString().startsWith(s);
});
ajv.addFormat('date-time', (s) => /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/.test(s) && !Number.isNaN(Date.parse(s)));
ajv.addSchema({ $id: SCHEMAS_ID, $defs: toJsonSchema(contract.components.schemas) });

const validators = new Map();
function validatorFor(schema) {
  const key = JSON.stringify(schema);
  if (!validators.has(key)) validators.set(key, ajv.compile(toJsonSchema(schema)));
  return validators.get(key);
}

/** Every operation in the contract, at the full path it is served on: { method, path, server, owner, operation }. */
function operations() {
  const out = [];
  for (const [template, item] of Object.entries(contract.paths)) {
    const server = (item.servers || contract.servers)[0];
    const url = server.url.replace(/\{(\w+)\}/g, (_, name) => server.variables[name].default);
    const base = new URL(url).pathname.replace(/\/$/, '');
    for (const method of METHODS) {
      if (!item[method]) continue;
      out.push({ method: method.toUpperCase(), path: base + template, server: server.url, owner: item[method]['x-owner'], operation: item[method] });
    }
  }
  return out;
}

function operation(method, fullPath) {
  const found = operations().find((op) => op.method === method && op.path === fullPath);
  if (!found) throw new Error(`the contract has no ${method} ${fullPath}`);
  return found;
}

/** Whether the contract has the operation yet. */
const documents = (method, fullPath) => operations().some((op) => op.method === method && op.path === fullPath);

/** The error codes a response documents: those in its examples and those named in `backticks` in its description. */
function documentedCodes(response) {
  const codes = new Set();
  for (const m of String(response.description || '').matchAll(/`([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*)`/g)) codes.add(m[1]);
  const media = response.content && response.content['application/json'];
  for (const example of Object.values((media && media.examples) || {})) {
    const value = deref(example).value;
    if (value && typeof value.code === 'string') codes.add(value.code);
  }
  return codes;
}

/**
 * Everything about a supertest reply that disagrees with the contract's entry for the operation,
 * as a list of sentences; [] when the reply is exactly what the contract promises.
 */
function contractProblems(op, res) {
  const responses = op.operation.responses;
  const key = responses[String(res.status)] ? String(res.status) : 'default';
  if (!responses[key]) return [`${op.method} ${op.path} does not document ${res.status}`];
  const documented = deref(responses[key]);
  // 204 No Content: documented with no body, and sent with none.
  if (res.status === 204) {
    const problems = [];
    if (documented.content) problems.push(`${op.method} ${op.path} documents a body for 204`);
    if (res.text) problems.push('a 204 reply carried a body');
    return problems;
  }
  const media = documented.content && documented.content['application/json'];
  if (!media) return [`${op.method} ${op.path} ${key} documents no JSON reply`];

  const problems = [];
  if (!/^application\/json\b/.test(res.headers['content-type'] || '')) problems.push(`the reply is ${res.headers['content-type']}, not JSON`);
  const validate = validatorFor(media.schema);
  if (!validate(res.body)) {
    for (const e of validate.errors) {
      const detail = e.params && e.params.additionalProperty ? ` (${e.params.additionalProperty})` : '';
      problems.push(`body${e.instancePath} ${e.message}${detail}`);
    }
  }
  if (res.status >= 400 && !documentedCodes(documented).has(res.body && res.body.code)) {
    problems.push(`code ${res.body && res.body.code} is not documented for ${res.status} (${key})`);
  }
  for (const [name, header] of Object.entries(documented.headers || {})) {
    const value = res.headers[name.toLowerCase()];
    const schema = deref(header).schema || {};
    if (value === undefined) problems.push(`header ${name} is missing`);
    else if (schema.const !== undefined && value !== schema.const) problems.push(`header ${name} is ${value}, not ${schema.const}`);
    else if (schema.type === 'integer' && !/^\d+$/.test(value)) problems.push(`header ${name} is ${value}, not an integer`);
  }
  return problems;
}

/**
 * The routes an Express 4 app serves under /api/ess, as 'GET /api/ess/me'. This reads Express's
 * own router stack, so it lists what is really mounted rather than what a test remembers. A path
 * parameter is spelt as the contract spells it: /sessions/:id is /sessions/{id}.
 */
function essRoutes(app) {
  const routes = [];
  for (const layer of app._router.stack) {
    if (layer.name !== 'router' || !layer.regexp.test('/api/ess')) continue;
    for (const inner of layer.handle.stack) {
      if (!inner.route) continue;
      const route = inner.route.path.replace(/:(\w+)/g, '{$1}');
      for (const method of Object.keys(inner.route.methods)) routes.push(`${method.toUpperCase()} /api/ess${route}`);
    }
  }
  return routes.sort();
}

module.exports = { contract, deref, operations, operation, documents, documentedCodes, contractProblems, essRoutes, CONTRACT_FILE };
