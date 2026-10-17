#!/usr/bin/env node
// Publishes MovieCat to the Mac App Store via the App Store Connect API.
//
//   node appstore/publish.mjs            # upload build + fill in the listing
//   node appstore/publish.mjs --submit   # ...and submit for App Review
//
// Needs appstore/asc.local.json (git-ignored):
//   { "keyId": "...", "issuerId": "...", "keyPath": "~/.appstoreconnect/private_keys/AuthKey_XXX.p8" }
// and appstore/review_contact.json (git-ignored) with contactFirstName/LastName/Phone/Email.
//
// Every step is idempotent, so the script can be re-run after fixing a problem.
// Apple's API cannot create the app record or answer the App Privacy questions;
// those two steps are done once on appstoreconnect.apple.com (see appstore/README.md).

import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const submit = process.argv.includes('--submit');
const meta = JSON.parse(fs.readFileSync(path.join(here, 'metadata.json'), 'utf8'));
const cfg = JSON.parse(fs.readFileSync(path.join(here, 'asc.local.json'), 'utf8'));
const contact = JSON.parse(fs.readFileSync(path.join(here, 'review_contact.json'), 'utf8'));
const keyPath = cfg.keyPath.replace(/^~/, os.homedir());
const privateKey = fs.readFileSync(keyPath, 'utf8');

const pubspec = fs.readFileSync(path.join(root, 'pubspec.yaml'), 'utf8');
const [, versionName, buildNumber] = pubspec.match(/^version:\s*([\d.]+)\+(\d+)/m);
const pkgPath = path.join(root, 'build/macos/export/MovieCat.pkg');

const log = (...a) => console.log('•', ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------- API client

function token() {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${b64({ alg: 'ES256', kid: cfg.keyId, typ: 'JWT' })}.${b64({
    iss: cfg.issuerId, iat: now, exp: now + 1100, aud: 'appstoreconnect-v1',
  })}`;
  const sig = crypto.sign('sha256', Buffer.from(unsigned), { key: privateKey, dsaEncoding: 'ieee-p1363' });
  return `${unsigned}.${sig.toString('base64url')}`;
}

async function api(method, p, body) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${p}`, {
    method,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 204) return null;
  const text = await res.text();
  const json = text ? JSON.parse(text) : null;
  if (!res.ok) {
    const detail = (json?.errors ?? []).map((e) => `${e.title}: ${e.detail}`).join('\n  ');
    const err = new Error(`${method} ${p} -> ${res.status}\n  ${detail}`);
    err.status = res.status;
    throw err;
  }
  return json;
}
const get = (p) => api('GET', p);
const rel = (type, id) => ({ data: { type, id } });

// ---------------------------------------------------------------- steps

async function findApp() {
  const r = await get(`/v1/apps?filter[bundleId]=${meta.bundleId}`);
  const app = r.data.find((a) => a.attributes.bundleId === meta.bundleId);
  if (!app) {
    console.error(`\nNo App Store Connect app with bundle ID ${meta.bundleId} yet.
Create it once at https://appstoreconnect.apple.com/apps  (+ > New App):
  Platform: macOS · Name: ${meta.name} · Language: English (U.S.)
  Bundle ID: ${meta.bundleId} · SKU: ${meta.sku} · Full Access
Then run this script again.\n`);
    process.exit(2);
  }
  log(`App: ${app.attributes.name} (${app.id})`);
  return app;
}

async function findBuild(appId) {
  const r = await get(`/v1/builds?filter[app]=${appId}&filter[version]=${buildNumber}` +
    `&filter[preReleaseVersion.platform]=MAC_OS&filter[preReleaseVersion.version]=${versionName}`);
  return r.data[0];
}

async function uploadBuild(app) {
  let build = await findBuild(app.id);
  if (!build) {
    if (!fs.existsSync(pkgPath)) throw new Error(`Package not found: ${pkgPath} (run appstore/build.sh)`);
    log(`Uploading ${path.relative(root, pkgPath)} (${versionName} build ${buildNumber})…`);
    const r = spawnSync('xcrun', ['altool', '--upload-package', pkgPath, '-t', 'osx',
      '--apple-id', app.id, '--bundle-id', meta.bundleId,
      '--bundle-version', buildNumber, '--bundle-short-version-string', versionName,
      '--api-key', cfg.keyId, '--api-issuer', cfg.issuerId], { stdio: 'inherit' });
    if (r.status !== 0) throw new Error('altool upload failed');
  } else {
    log(`Build ${versionName} (${buildNumber}) already uploaded`);
  }
  // Wait for Apple to process it.
  for (let i = 0; i < 120; i++) {
    build = await findBuild(app.id);
    const state = build?.attributes.processingState;
    if (state === 'VALID') { log('Build processed'); return build; }
    if (state === 'INVALID' || state === 'FAILED') throw new Error(`Build processing ${state}`);
    if (!build) {
      // Before the build shows up, a rejected upload is only visible here.
      const uploads = await get(`/v1/apps/${app.id}/buildUploads?limit=20`).catch(() => ({ data: [] }));
      const upload = uploads.data.find((u) => u.attributes.cfBundleVersion === buildNumber);
      if (upload?.attributes.state?.state === 'FAILED') {
        const errors = upload.attributes.state.errors.map((e) => `${e.code}: ${e.description}`).join('\n  ');
        throw new Error(`Apple rejected build ${buildNumber}:\n  ${errors}`);
      }
    }
    log(`Waiting for build processing (${state ?? 'not visible yet'})…`);
    await sleep(30000);
  }
  throw new Error('Timed out waiting for build processing');
}

async function ensureVersion(appId) {
  const r = await get(`/v1/apps/${appId}/appStoreVersions?filter[platform]=MAC_OS&limit=50`);
  const editable = ['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED', 'INVALID_BINARY'];
  let v = r.data.find((x) => editable.includes(x.attributes.appStoreState ?? x.attributes.appVersionState));
  const attributes = { versionString: versionName, copyright: meta.copyright, releaseType: 'AFTER_APPROVAL' };
  if (!v) {
    v = (await api('POST', '/v1/appStoreVersions', {
      data: { type: 'appStoreVersions', attributes: { platform: 'MAC_OS', ...attributes },
        relationships: { app: rel('apps', appId) } },
    })).data;
    log(`Created version ${versionName}`);
  } else {
    await api('PATCH', `/v1/appStoreVersions/${v.id}`, { data: { type: 'appStoreVersions', id: v.id, attributes } });
    log(`Version ${versionName} (${v.id}) updated`);
  }
  return v;
}

async function versionLocalization(versionId) {
  const attributes = {
    description: meta.description, keywords: meta.keywords, promotionalText: meta.promotionalText,
    supportUrl: meta.supportUrl, marketingUrl: meta.marketingUrl,
  };
  const r = await get(`/v1/appStoreVersions/${versionId}/appStoreVersionLocalizations`);
  let loc = r.data.find((l) => l.attributes.locale === meta.primaryLocale);
  if (loc) {
    await api('PATCH', `/v1/appStoreVersionLocalizations/${loc.id}`,
      { data: { type: 'appStoreVersionLocalizations', id: loc.id, attributes } });
  } else {
    loc = (await api('POST', '/v1/appStoreVersionLocalizations', {
      data: { type: 'appStoreVersionLocalizations', attributes: { locale: meta.primaryLocale, ...attributes },
        relationships: { appStoreVersion: rel('appStoreVersions', versionId) } },
    })).data;
  }
  log('Description, keywords and URLs set');
  return loc;
}

async function appInfo(appId) {
  const r = await get(`/v1/apps/${appId}/appInfos`);
  const info = r.data.find((i) => !['READY_FOR_DISTRIBUTION', 'READY_FOR_SALE'].includes(
    i.attributes.state ?? i.attributes.appStoreState)) ?? r.data[0];
  await api('PATCH', `/v1/appInfos/${info.id}`, {
    data: { type: 'appInfos', id: info.id, relationships: {
      primaryCategory: rel('appCategories', meta.primaryCategory),
      secondaryCategory: rel('appCategories', meta.secondaryCategory),
    } },
  });
  const locs = await get(`/v1/appInfos/${info.id}/appInfoLocalizations`);
  const loc = locs.data.find((l) => l.attributes.locale === meta.primaryLocale);
  const attributes = { name: meta.name, subtitle: meta.subtitle, privacyPolicyUrl: meta.privacyPolicyUrl };
  if (loc) {
    await api('PATCH', `/v1/appInfoLocalizations/${loc.id}`, { data: { type: 'appInfoLocalizations', id: loc.id, attributes } });
  } else {
    await api('POST', '/v1/appInfoLocalizations', { data: { type: 'appInfoLocalizations',
      attributes: { locale: meta.primaryLocale, ...attributes }, relationships: { appInfo: rel('appInfos', info.id) } } });
  }
  log('Name, subtitle, category and privacy policy set');
  return info;
}

async function ageRating(infoId) {
  const r = await get(`/v1/appInfos/${infoId}/ageRatingDeclaration`);
  const current = r.data.attributes;
  // No objectionable content. "advertising" is true because of the ABCx3 cross-promotion banner.
  const booleans = {
    advertising: true, gambling: false, healthOrWellnessTopics: false, lootBox: false,
    messagingAndChat: false, parentalControls: false, ageAssurance: false, socialMedia: false,
    socialMediaAgeRestricted: false, unrestrictedWebAccess: false, userGeneratedContent: false,
  };
  const levels = ['alcoholTobaccoOrDrugUseOrReferences', 'contests', 'gamblingSimulated', 'gunsOrOtherWeapons',
    'medicalOrTreatmentInformation', 'profanityOrCrudeHumor', 'sexualContentGraphicAndNudity',
    'sexualContentOrNudity', 'horrorOrFearThemes', 'matureOrSuggestiveThemes', 'violenceCartoonOrFantasy',
    'violenceRealisticProlongedGraphicOrSadistic', 'violenceRealistic'];
  const attributes = {};
  for (const k of Object.keys(current)) {
    if (k in booleans) attributes[k] = booleans[k];
    else if (levels.includes(k)) attributes[k] = 'NONE';
  }
  await api('PATCH', `/v1/ageRatingDeclarations/${r.data.id}`,
    { data: { type: 'ageRatingDeclarations', id: r.data.id, attributes } });
  log('Age rating questionnaire answered');
}

async function contentRights(appId) {
  await api('PATCH', `/v1/apps/${appId}`, { data: { type: 'apps', id: appId,
    attributes: { contentRightsDeclaration: meta.contentRightsDeclaration } } });
  log(`Content rights: ${meta.contentRightsDeclaration}`);
}

async function pricing(appId) {
  try {
    await get(`/v1/apps/${appId}/appPriceSchedule`);
    const prices = await get(`/v1/appPriceSchedules/${appId}/manualPrices?limit=1`);
    if (prices.data.length) { log('Price already set'); return; }
  } catch (e) { if (e.status !== 404) throw e; }
  const points = await get(`/v1/apps/${appId}/appPricePoints?filter[territory]=USA&limit=200`);
  const free = points.data.find((pp) => Number(pp.attributes.customerPrice) === 0);
  if (!free) throw new Error('Free price point not found');
  await api('POST', '/v1/appPriceSchedules', {
    data: { type: 'appPriceSchedules', relationships: {
      app: rel('apps', appId), baseTerritory: rel('territories', 'USA'),
      manualPrices: { data: [{ type: 'appPrices', id: '${free}' }] } } },
    included: [{ type: 'appPrices', id: '${free}', attributes: { startDate: null },
      relationships: { appPricePoint: rel('appPricePoints', free.id) } }],
  });
  log('Price set to Free');
}

async function availability(appId) {
  try {
    await get(`/v1/apps/${appId}/appAvailabilityV2`);
    log('Availability already set');
    return;
  } catch (e) { if (e.status !== 404) throw e; }
  const territories = [];
  let next = '/v1/territories?limit=200';
  while (next) {
    const r = await get(next);
    territories.push(...r.data.map((t) => t.id));
    next = r.links?.next ? r.links.next.replace('https://api.appstoreconnect.apple.com', '') : null;
  }
  await api('POST', '/v2/appAvailabilities', {
    data: { type: 'appAvailabilities', attributes: { availableInNewTerritories: true },
      relationships: { app: rel('apps', appId), territoryAvailabilities: {
        data: territories.map((t) => ({ type: 'territoryAvailabilities', id: `\${${t}}` })) } } },
    included: territories.map((t) => ({ type: 'territoryAvailabilities', id: `\${${t}}`,
      attributes: { available: true }, relationships: { territory: rel('territories', t) } })),
  });
  log(`Available in all ${territories.length} territories`);
}

async function reviewDetails(versionId) {
  const attributes = { ...contact, demoAccountRequired: false, notes: meta.reviewNotes };
  let existing = null;
  try { existing = (await get(`/v1/appStoreVersions/${versionId}/appStoreReviewDetail`)).data; } catch (e) {
    if (e.status !== 404) throw e;
  }
  if (existing) {
    await api('PATCH', `/v1/appStoreReviewDetails/${existing.id}`,
      { data: { type: 'appStoreReviewDetails', id: existing.id, attributes } });
  } else {
    await api('POST', '/v1/appStoreReviewDetails', { data: { type: 'appStoreReviewDetails', attributes,
      relationships: { appStoreVersion: rel('appStoreVersions', versionId) } } });
  }
  log('App Review contact and notes set');
}

async function screenshots(localizationId) {
  const sets = await get(`/v1/appStoreVersionLocalizations/${localizationId}/appScreenshotSets`);
  let set = sets.data.find((s) => s.attributes.screenshotDisplayType === 'APP_DESKTOP');
  if (!set) {
    set = (await api('POST', '/v1/appScreenshotSets', { data: { type: 'appScreenshotSets',
      attributes: { screenshotDisplayType: 'APP_DESKTOP' },
      relationships: { appStoreVersionLocalization: rel('appStoreVersionLocalizations', localizationId) } } })).data;
  }
  const files = meta.screenshots.map((f) => path.join(here, f));
  const existing = (await get(`/v1/appScreenshotSets/${set.id}/appScreenshots?limit=50`)).data;
  const names = existing.map((s) => s.attributes.fileName).join('|');
  if (names === files.map((f) => path.basename(f)).join('|') &&
      existing.every((s) => s.attributes.assetDeliveryState?.state === 'COMPLETE')) {
    log('Screenshots already uploaded');
    return;
  }
  for (const s of existing) await api('DELETE', `/v1/appScreenshots/${s.id}`);
  for (const file of files) {
    const bytes = fs.readFileSync(file);
    const shot = (await api('POST', '/v1/appScreenshots', { data: { type: 'appScreenshots',
      attributes: { fileName: path.basename(file), fileSize: bytes.length },
      relationships: { appScreenshotSet: rel('appScreenshotSets', set.id) } } })).data;
    for (const op of shot.attributes.uploadOperations) {
      const headers = Object.fromEntries((op.requestHeaders ?? []).map((h) => [h.name, h.value]));
      const res = await fetch(op.url, { method: op.method, headers,
        body: bytes.subarray(op.offset, op.offset + op.length) });
      if (!res.ok) throw new Error(`Screenshot upload failed: ${res.status}`);
    }
    await api('PATCH', `/v1/appScreenshots/${shot.id}`, { data: { type: 'appScreenshots', id: shot.id,
      attributes: { uploaded: true, sourceFileChecksum: crypto.createHash('md5').update(bytes).digest('hex') } } });
    log(`Uploaded ${path.basename(file)}`);
  }
}

async function attachBuild(versionId, buildId) {
  await api('PATCH', `/v1/appStoreVersions/${versionId}/relationships/build`, { data: { type: 'builds', id: buildId } });
  log('Build attached to version');
}

async function submitForReview(appId, versionId) {
  const open = await get(`/v1/reviewSubmissions?filter[app]=${appId}&filter[platform]=MAC_OS&filter[state]=READY_FOR_REVIEW`);
  let sub = open.data[0];
  if (!sub) {
    sub = (await api('POST', '/v1/reviewSubmissions', { data: { type: 'reviewSubmissions',
      attributes: { platform: 'MAC_OS' }, relationships: { app: rel('apps', appId) } } })).data;
  }
  try {
    await api('POST', '/v1/reviewSubmissionItems', { data: { type: 'reviewSubmissionItems', relationships: {
      reviewSubmission: rel('reviewSubmissions', sub.id), appStoreVersion: rel('appStoreVersions', versionId) } } });
  } catch (e) {
    if (e.status !== 409) throw e; // already added
  }
  await api('PATCH', `/v1/reviewSubmissions/${sub.id}`, { data: { type: 'reviewSubmissions', id: sub.id,
    attributes: { submitted: true } } });
  log('Submitted for App Review 🎉');
}

// ---------------------------------------------------------------- main

const app = await findApp();
const build = await uploadBuild(app);
const version = await ensureVersion(app.id);
const loc = await versionLocalization(version.id);
const info = await appInfo(app.id);
await ageRating(info.id);
await contentRights(app.id);
await pricing(app.id);
await availability(app.id);
await reviewDetails(version.id);
await screenshots(loc.id);
await attachBuild(version.id, build.id);
if (submit) {
  await submitForReview(app.id, version.id);
} else {
  log('Everything is filled in. Run again with --submit to send it to App Review.');
}
