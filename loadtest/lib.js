// 부하 테스트 공용. 서버는 app.member.social.fake=true로 띄운다(토큰 문자열 = 소셜 ID).
import http from 'k6/http';
import { Trend, Counter } from 'k6/metrics';

export const BASE = __ENV.BASE || 'http://host.docker.internal:8090';
// 분리 실험: run 요청만 다른 인스턴스로(같은 DB). 비우면 BASE
const RUN_BASE = __ENV.RUN_BASE || BASE;
export const MODULES = ['member', 'course', 'run', 'ranking', 'review', 'notification'];

// 모듈별 응답 시간 · 실패 수. handleSummary가 모듈 단위로 모은다
const latency = {}, failures = {};
for (const m of MODULES) {
  latency[m] = new Trend(`lat_${m}`, true);
  failures[m] = new Counter(`fail_${m}`);
}

// 여정(사용자 흐름)별 응답 시간. load.js가 여정을 시작할 때 setJourney로 알린다
export const JOURNEY_NAMES = ['home', 'detail', 'run', 'register', 'ranking', 'my'];
const journeyLatency = {}, journeyFailures = {};
for (const j of JOURNEY_NAMES) {
  journeyLatency[j] = new Trend(`jlat_${j}`, true);
  journeyFailures[j] = new Counter(`jfail_${j}`);
}
let current = null;
export function setJourney(name) { current = name; }

function call(method, module, path, token, body, name, headers) {
  const params = {
    headers: Object.assign({ 'Content-Type': 'application/json' }, headers),
    tags: { module, name: name || path },
    timeout: __ENV.SEED ? '60s' : '15s', // 앱의 응답 제한(api_client.dart receiveTimeout 15초). 넘으면 앱에서는 오류다
  };
  if (token) params.headers.Authorization = `Bearer ${token}`;
  const res = http.request(method, (module === 'run' ? RUN_BASE : BASE) + path, body === undefined ? null : JSON.stringify(body), params);
  latency[module].add(res.timings.duration);
  if (current) journeyLatency[current].add(res.timings.duration);
  if (res.status >= 400 || res.status === 0) {
    failures[module].add(1);
    if (current) journeyFailures[current].add(1);
    if (__ENV.DEBUG) console.warn(`${method} ${path} → ${res.status} ${String(res.body).slice(0, 200)}`);
  }
  return res;
}

export const get = (m, p, t, n) => call('GET', m, p, t, undefined, n);
export const post = (m, p, t, b, n, h) => call('POST', m, p, t, b, n, h);
export const put = (m, p, t, b, n) => call('PUT', m, p, t, b, n);

export function data(res) {
  try { return res.json('data'); } catch (e) { return null; }
}

/** 가입돼 있으면 로그인, 아니면 가입. access token을 돌려준다 */
export function login(i) {
  const res = post('member', '/api/v1/members/auth/login', null, { provider: 'KAKAO', token: `lt-user-${i}` }, 'login');
  const d = data(res);
  if (d && d.tokens) return d.tokens.accessToken;
  const signup = post('member', '/api/v1/members/auth/signup', null, {
    signupToken: d.signupToken,
    agreements: { over14: true, serviceTerms: true, privacyPolicy: true, locationTerms: true, profileInfo: true },
    nickname: `부하${i}`,
    regionCode: REGIONS[i % REGIONS.length],
    runningExperience: 'YEAR_1',
  }, 'signup');
  return data(signup).accessToken;
}

// 서울 자치구 몇 곳(활동 지역 · 지역 주간 랭킹)
export const REGIONS = ['1168000000', '1165000000', '1171000000', '1144000000', '1156000000', '1111000000'];

// 서울 안 무작위 위치
export const AREA = { swLat: 37.45, swLng: 126.85, neLat: 37.65, neLng: 127.15 };

/** 결정적 난수(시드 번호마다 같은 코스 · 같은 기록) */
export function rng(seed) {
  let s = (seed * 2654435761) >>> 0;
  return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
}

/** i번째 코스: 서울 안 중심, 반지름 300~700m의 8각형 고리(2~4.4km). 첫 점으로 돌아온다 */
export function courseAnchors(i) {
  const r = rng(i + 1);
  const lat = AREA.swLat + 0.01 + r() * (AREA.neLat - AREA.swLat - 0.02);
  const lng = AREA.swLng + 0.01 + r() * (AREA.neLng - AREA.swLng - 0.02);
  const radius = 300 + r() * 400;
  const pts = [];
  for (let k = 0; k <= 8; k++) {
    const a = (Math.PI * 2 * k) / 8;
    pts.push({ lat: lat + (radius * Math.sin(a)) / 111320, lng: lng + (radius * Math.cos(a)) / (111320 * Math.cos(lat * Math.PI / 180)) });
  }
  return pts;
}

function dist(a, b) {
  const dLat = (b.lat - a.lat) * 111320;
  const dLng = (b.lng - a.lng) * 111320 * Math.cos(a.lat * Math.PI / 180);
  return Math.sqrt(dLat * dLat + dLng * dLng);
}

/** 경로를 따라 speed(m/s)로 1초마다 찍은 점. maxSeconds가 있으면 경로를 되풀이해 그 시간만큼 */
export function walk(path, speed, maxSeconds) {
  const out = [path[0]];
  let seg = 0, along = 0;
  const total = maxSeconds || Infinity;
  for (let t = 1; t <= total; t++) {
    let step = speed;
    while (step > 0) {
      if (seg >= path.length - 1) {
        if (!maxSeconds) return out;
        seg = 0; // 고리를 한 바퀴 더
      }
      const len = dist(path[seg], path[seg + 1]);
      if (along + step < len) { along += step; step = 0; }
      else { step -= len - along; along = 0; seg++; }
    }
    if (seg >= path.length - 1) { out.push(path[path.length - 1]); if (!maxSeconds) return out; continue; }
    const a = path[seg], b = path[seg + 1], f = along / dist(a, b);
    out.push({ lat: a.lat + (b.lat - a.lat) * f, lng: a.lng + (b.lng - a.lng) * f });
  }
  return out;
}

/** 앱이 올리는 원본 입력: START, 1초마다 GPS, 5초마다 CADENCE, (코스면 SEGMENT_END), PAUSE, END */
export function inputs(startedAtMs, points, course) {
  const list = [];
  const at = (ms) => new Date(startedAtMs + ms).toISOString();
  list.push({ seq: 0, kind: 'START', elapsedMs: 0, measuredAt: at(0), reason: 'PACE_V2' });
  points.forEach((p, t) => {
    const ms = t * 1000;
    list.push({ seq: list.length, kind: 'GPS', elapsedMs: ms, measuredAt: at(ms), location: p, accuracyM: 4, speedMps: 3, speedAccuracyMps: 0.3, altitudeM: 30, altitudeAccuracyM: 3 });
    if (t > 0 && t % 5 === 0) list.push({ seq: list.length, kind: 'CADENCE', elapsedMs: ms, measuredAt: at(ms), steps: 14, durationMs: 5000, sampleEndMs: ms });
  });
  const end = (points.length - 1) * 1000;
  if (course) list.push({ seq: list.length, kind: 'SEGMENT_END', elapsedMs: end, measuredAt: at(end), reason: 'ARRIVED' });
  // 사용자가 끝내면 앱은 일시정지 → 종료 순서로 남긴다(END USER는 정지 상태에서만)
  list.push({ seq: list.length, kind: 'PAUSE', elapsedMs: end, measuredAt: at(end) });
  list.push({ seq: list.length, kind: 'END', elapsedMs: end, measuredAt: at(end), reason: 'USER' });
  return list;
}

export function uuid() {
  // UUID v4 형식(세션 ID는 앱이 만든다)
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}

/** 기록 업로드(500개씩). course가 있으면 코스 러닝 준비 · 시작 신호를 먼저 보낸다 */
export function runSession(token, points, courseId) {
  const id = uuid();
  const startedAtMs = Date.now() - points.length * 1000 - 60000;
  const startedAt = new Date(startedAtMs).toISOString();
  if (courseId) {
    put('run', `/api/v1/runs/sessions/${id}/course`, token, { courseId }, 'course-prepare');
    post('run', `/api/v1/runs/sessions/${id}/course/start`, token, { startedAt }, 'course-start');
  }
  put('run', `/api/v1/runs/sessions/${id}`, token, { startedAt, mode: courseId ? 'COURSE' : 'FREE' }, 'session-prepare');
  if (courseId) post('run', `/api/v1/runs/sessions/${id}/course/segment-end`, token, undefined, 'segment-end');
  const all = inputs(startedAtMs, points, !!courseId);
  const finalSeq = all.length - 1;
  for (let k = 0; k < all.length; k += 500) {
    post('run', `/api/v1/runs/sessions/${id}/record`, token, { finalSeq, inputs: all.slice(k, k + 500) }, 'record-upload');
  }
  return id;
}

function summary(d, names, lat, fail) {
  const rows = {};
  for (const m of names) {
    const t = d.metrics[`${lat}_${m}`];
    if (!t) continue;
    rows[m] = {
      requests: t.values.count,
      failed: d.metrics[`${fail}_${m}`] ? d.metrics[`${fail}_${m}`].values.count : 0,
      avg: +t.values.avg.toFixed(1), p95: +t.values['p(95)'].toFixed(1), max: +t.values.max.toFixed(1),
    };
  }
  return rows;
}
/** k6 요약을 모듈별 · 여정별 표로 */
export const moduleSummary = (d) => summary(d, MODULES, 'lat', 'fail');
export const journeySummary = (d) => summary(d, JOURNEY_NAMES, 'jlat', 'jfail');
