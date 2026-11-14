// 모듈별 사용자 흐름(여정). MODULE=course처럼 하나만 돌리면 그 모듈의 비용을, MODULE=mix면 사용 비율대로 섞어 돌린다.
//   RATE: 초당 여정 수, DURATION: 시간, PROBE=1: 다른 모듈 응답 시간을 재는 가벼운 탐침을 함께 돌린다(간섭 측정)
import { sleep } from 'k6';
import exec from 'k6/execution';
import encoding from 'k6/encoding';
import { login, get, put, post, data, walk, courseAnchors, runSession, uuid, AREA, REGIONS, moduleSummary } from './lib.js';

const MODULE = __ENV.MODULE || 'mix';
const RATE = +(__ENV.RATE || 10);
const DURATION = __ENV.DURATION || '60s';
const USERS = +(__ENV.USERS || 300);
const USER_OFFSET = +(__ENV.USER_OFFSET || 0); // 코스 등록은 오늘 한도를 안 쓴 새 회원(예: 1000번부터)으로
const STATE_FILE = `results/${__ENV.STATE || 'state'}.json`;

// 활성 사용자 1명이 1시간에 하는 여정 수(가정, 정책 문서의 화면 흐름 기준). mix는 이 비율로 고른다
export const WEIGHTS = {
  course: 6,        // 홈 지도 · 목록 · 현재 러너 수 · 코스 상세
  notification: 4,  // 앱 열 때마다 안 읽은 알림 수
  run: 1,           // 러닝 1회 = 기록 업로드 + 결과 · 구간 · 기록 목록
  ranking: 2,
  review: 2,
  member: 2,
};

const scenarios = {
  main: {
    executor: 'constant-arrival-rate', rate: RATE, timeUnit: '1s', duration: DURATION,
    preAllocatedVUs: Math.max(20, RATE * 4), maxVUs: Math.max(100, RATE * 20), exec: 'journey',
  },
};
if (__ENV.PROBE) {
  scenarios.probe = { executor: 'constant-arrival-rate', rate: 5, timeUnit: '1s', duration: DURATION, preAllocatedVUs: 10, maxVUs: 50, exec: 'probe' };
}
export const options = { scenarios, summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max', 'count'], setupTimeout: '300s' };

// 로그인 비용이 측정에 섞이지 않게, SAVE=1로 한 번 만든 토큰 · 코스 목록(results/state.json, 토큰 1시간)을 다시 쓴다
let STATE = null;
try { STATE = JSON.parse(open(`./${STATE_FILE}`)); } catch (e) { /* 아직 없음 */ }

export function setup() {
  if (STATE && !__ENV.SAVE) return STATE;
  const tokens = [];
  for (let i = USER_OFFSET; i < USER_OFFSET + USERS; i++) tokens.push(login(i));
  const courses = [];
  let cursor = '';
  do {
    const q = `swLat=${AREA.swLat}&swLng=${AREA.swLng}&neLat=${AREA.neLat}&neLng=${AREA.neLng}&sort=LATEST&size=50${cursor ? `&cursor=${cursor}` : ''}`;
    const d = data(get('course', `/api/v1/courses?${q}`, tokens[0], 'course-list'));
    d.content.forEach((c) => courses.push({ id: c.courseId, route: c.route, lat: c.route[0].lat, lng: c.route[0].lng }));
    cursor = d.nextCursor;
  } while (cursor);
  const memberIds = tokens.slice(0, Math.min(50, tokens.length)).map((t) => JSON.parse(encoding.b64decode(t.split('.')[1], 'rawurl', 's')).sub);
  return { tokens, courses, memberIds };
}

const pickOne = (arr) => arr[Math.floor(Math.random() * arr.length)];

function pickModule() {
  if (MODULE !== 'mix') return MODULE;
  const total = Object.values(WEIGHTS).reduce((a, b) => a + b, 0);
  let r = Math.random() * total;
  for (const [m, w] of Object.entries(WEIGHTS)) { if ((r -= w) < 0) return m; }
  return 'course';
}

// 화면 하나 크기(약 2km)의 지도 범위
function viewport(c) {
  return `swLat=${(c.lat - 0.009).toFixed(5)}&swLng=${(c.lng - 0.011).toFixed(5)}&neLat=${(c.lat + 0.009).toFixed(5)}&neLng=${(c.lng + 0.011).toFixed(5)}`;
}

const JOURNEYS = {
  idle() {}, // 간섭 측정의 기준선(탐침만)
  course(s, token) {
    const c = pickOne(s.courses);
    const vp = viewport(c);
    get('course', `/api/v1/courses/map?${vp}`, token, 'map');
    const list = data(get('course', `/api/v1/courses?${vp}&sort=POPULAR&size=20`, token, 'list'));
    const ids = (list && list.content.length ? list.content : [{ courseId: c.id }]).map((x) => x.courseId);
    get('course', `/api/v1/courses/active-runners?${ids.map((id) => `courseIds=${id}`).join('&')}`, token, 'active-runners');
    if (Math.random() < 0.3) get('course', `/api/v1/courses/map/regions?swLat=${AREA.swLat}&swLng=${AREA.swLng}&neLat=${AREA.neLat}&neLng=${AREA.neLng}&level=CITY`, token, 'map-regions');
    get('course', `/api/v1/courses/${pickOne(ids)}`, token, 'detail');
    if (Math.random() < 0.2) get('course', '/api/v1/courses/bookmarks', token, 'bookmarks');
  },
  run(s, token, i) {
    // 절반은 코스 러닝(약 15~25분), 절반은 자유 러닝 30분
    let id;
    if (Math.random() < 0.5) {
      const c = pickOne(s.courses);
      id = runSession(token, walk(c.route, 3), c.id);
    } else {
      id = runSession(token, walk(courseAnchors(5000 + i), 3, 1800));
    }
    get('run', `/api/v1/runs/sessions/${id}/status`, token, 'status');
    get('run', '/api/v1/runs/records?size=20', token, 'records');
  },
  ranking(s, token) {
    const c = pickOne(s.courses);
    get('ranking', `/api/v1/rankings/courses/${c.id}?period=ALL`, token, 'course-ranking');
    get('ranking', `/api/v1/rankings/courses/${c.id}/entries?period=MONTH`, token, 'course-entries');
    get('ranking', '/api/v1/rankings/distance?period=ALL', token, 'distance');
    get('ranking', `/api/v1/rankings/distance/regions/weekly?regionCode=${pickOne(REGIONS)}`, token, 'region-weekly');
  },
  review(s, token) {
    const c = pickOne(s.courses);
    get('review', `/api/v1/reviews/summary?courseId=${c.id}`, token, 'summary');
    get('review', `/api/v1/reviews?courseId=${c.id}&sort=LATEST`, token, 'list');
    if (Math.random() < 0.3) get('review', `/api/v1/reviews/me?courseId=${c.id}`, token, 'mine');
  },
  member(s, token) {
    get('member', '/api/v1/members/me', token, 'me');
    get('member', `/api/v1/members/${pickOne(s.memberIds)}`, token, 'profile');
    if (Math.random() < 0.3) get('member', `/api/v1/members/search?query=${encodeURIComponent('부하1')}`, token, 'search');
  },
  notification(s, token) {
    get('notification', '/api/v1/notifications/unread-count', token, 'unread');
    if (Math.random() < 0.3) get('notification', '/api/v1/notifications', token, 'list');
  },
  // 사용자 1명의 하루(러닝 1회). 화면별 호출은 앱 코드 기준(FrontEnd/app/lib, 2026-11-14):
  // 알림 종(notification_bell) → 홈(지도는 카메라가 멈출 때마다 home_screen._onCameraIdle, 목록 1번,
  // 현재 러너 수 1분마다 course_list_sheet) → 코스 상세 B1(상세 · 랭킹 요약 · 엔트리 · 리뷰 요약 · 내 리뷰)
  // → 러닝(코스 50% / 자유 30분 50%) → 상태 확인 · 결과 · 구간 → MY 기록 → 랭킹 탭
  day(s, token, i) {
    get('notification', '/api/v1/notifications/unread-count', token, 'unread');
    const c = pickOne(s.courses);
    for (let k = 0; k < 3; k++) get('course', `/api/v1/courses/map?${viewport(pickOne(s.courses))}`, token, 'map'); // 지도 3번 움직임
    const list = data(get('course', `/api/v1/courses?${viewport(c)}&sort=POPULAR&size=20`, token, 'list'));
    const ids = (list && list.content.length ? list.content : [{ courseId: c.id }]).map((x) => x.courseId);
    for (let k = 0; k < 3; k++) get('course', `/api/v1/courses/active-runners?${ids.map((id) => `courseIds=${id}`).join('&')}`, token, 'active-runners'); // 홈 3분
    get('course', `/api/v1/courses/${c.id}`, token, 'detail');
    get('ranking', `/api/v1/rankings/courses/${c.id}?period=ALL`, token, 'course-ranking');
    get('ranking', `/api/v1/rankings/courses/${c.id}/entries?period=ALL`, token, 'course-entries');
    get('review', `/api/v1/reviews/summary?courseId=${c.id}`, token, 'summary');
    get('review', `/api/v1/reviews/me?courseId=${c.id}`, token, 'mine');
    const id = Math.random() < 0.5 ? runSession(token, walk(c.route, 3), c.id) : runSession(token, walk(courseAnchors(5000 + i), 3, 1800));
    for (let k = 0; k < 2; k++) get('run', `/api/v1/runs/sessions/${id}/status`, token, 'status');
    get('run', `/api/v1/runs/records/${id}`, token, 'result');
    get('run', `/api/v1/runs/records/${id}/splits`, token, 'splits');
    get('run', '/api/v1/runs/records?size=20', token, 'records');
    get('ranking', '/api/v1/rankings/distance?period=ALL', token, 'distance');
    get('ranking', '/api/v1/rankings/distance/entries?period=ALL', token, 'distance-entries');
    get('ranking', `/api/v1/rankings/distance/regions/weekly?regionCode=${pickOne(REGIONS)}`, token, 'region-weekly');
  },
  // 사용자 지정 코스 등록(B3 → B5): 남은 한도 · 이름 확인 · 등록. 회원마다 하루 1번이라 USER_OFFSET으로 새 회원을 쓴다
  register(s, token, i) {
    const n = USER_OFFSET + (i % USERS);
    get('course', '/api/v1/courses/registration-quota', token, 'quota');
    get('course', `/api/v1/courses/name-availability?name=${encodeURIComponent(`부하코스${n}`)}`, token, 'name');
    post('course', '/api/v1/courses', token, { anchorPoints: courseAnchors(n), name: `부하코스${n}`, difficulty: 'MEDIUM', tags: [] }, 'register', { 'Idempotency-Key': uuid() });
  },
};

export function journey(s) {
  const i = exec.scenario.iterationInTest;
  const token = s.tokens[i % s.tokens.length];
  JOURNEYS[pickModule()](s, token, i);
}

// 간섭 측정용: 대상 모듈이 아닌 화면의 가벼운 조회 하나씩
export function probe(s) {
  const token = pickOne(s.tokens);
  const c = pickOne(s.courses);
  get('member', '/api/v1/members/me', token, 'probe');
  get('course', `/api/v1/courses/${c.id}`, token, 'probe');
  get('ranking', `/api/v1/rankings/courses/${c.id}?period=ALL`, token, 'probe');
  get('review', `/api/v1/reviews/summary?courseId=${c.id}`, token, 'probe');
  get('notification', '/api/v1/notifications/unread-count', token, 'probe');
}

export function handleSummary(d) {
  const http = d.metrics.http_req_duration.values, failed = d.metrics.http_req_failed.values;
  const out = { module: MODULE, rate: RATE, duration: DURATION, iterations: d.metrics.iterations ? d.metrics.iterations.values.count : 0,
    total: { requests: http.count, p95: +http['p(95)'].toFixed(1), p99: +http['p(99)'].toFixed(1), failRate: +(failed.rate * 100).toFixed(2) },
    modules: moduleSummary(d) };
  const files = { stdout: JSON.stringify(out, null, 1) + '\n', [`results/${__ENV.TAG || MODULE}.json`]: JSON.stringify(out, null, 1) };
  if (__ENV.SAVE) files[STATE_FILE] = JSON.stringify(d.setup_data);
  return files;
}
