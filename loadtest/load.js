// 여정(사용자 흐름)별 부하. JOURNEY=home처럼 하나만 돌리거나, JOURNEY=day로 사용자 1명의 하루를 통째로 돌린다.
//   RATE: 초당 여정 수, DURATION: 시간
//   PROBE=1: 모든 모듈의 가벼운 조회(탐침)를 초당 5번 함께 돌린다(간섭 측정)
//   RUN_BASE: run 요청만 다른 인스턴스로(분리 실험, lib.js)
// 화면별 호출은 앱 코드 기준이다(FrontEnd/app/lib, 2026-11-14). 모듈 단위 측정은 modules.js.
import exec from 'k6/execution';
import encoding from 'k6/encoding';
import { login, get, post, data, walk, courseAnchors, runSession, uuid, setJourney, AREA, REGIONS, moduleSummary, journeySummary } from './lib.js';

const JOURNEY = __ENV.JOURNEY || 'day';
const RATE = +(__ENV.RATE || 1);
const DURATION = __ENV.DURATION || '40s';
const USERS = +(__ENV.USERS || 600);
const TAG = __ENV.TAG || JOURNEY;

const scenarios = {
  main: {
    executor: 'constant-arrival-rate', rate: RATE, timeUnit: '1s', duration: DURATION,
    preAllocatedVUs: Math.max(20, RATE * 4), maxVUs: Math.max(200, RATE * 30), exec: 'journey',
  },
};
if (__ENV.PROBE) {
  scenarios.probe = { executor: 'constant-arrival-rate', rate: 5, timeUnit: '1s', duration: DURATION, preAllocatedVUs: 10, maxVUs: 50, exec: 'probe' };
}
export const options = { scenarios, summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max', 'count'], setupTimeout: '600s' };

// 로그인 비용이 측정에 섞이지 않게, SAVE=1로 한 번 만든 토큰 · 코스 목록(results/state.json, 토큰 1시간)을 다시 쓴다
let STATE = null;
try { STATE = JSON.parse(open('./results/state.json')); } catch (e) { /* 아직 없음 */ }

export function setup() {
  if (STATE && !__ENV.SAVE) return STATE;
  const tokens = [];
  for (let i = 0; i < USERS; i++) tokens.push(login(i));
  const courses = [];
  let cursor = '';
  do {
    const q = `swLat=${AREA.swLat}&swLng=${AREA.swLng}&neLat=${AREA.neLat}&neLng=${AREA.neLng}&sort=LATEST&size=50${cursor ? `&cursor=${cursor}` : ''}`;
    const d = data(get('course', `/api/v1/courses?${q}`, tokens[0], 'course-list'));
    d.content.forEach((c) => courses.push({ id: c.courseId, route: c.route, lat: c.route[0].lat, lng: c.route[0].lng }));
    cursor = d.nextCursor;
  } while (cursor);
  const memberIds = tokens.map((t) => JSON.parse(encoding.b64decode(t.split('.')[1], 'rawurl', 's')).sub);
  return { tokens, courses, memberIds };
}

const pickOne = (arr) => arr[Math.floor(Math.random() * arr.length)];

// 화면 하나 크기(약 2km)의 지도 범위
function viewport(c) {
  return `swLat=${(c.lat - 0.009).toFixed(5)}&swLng=${(c.lng - 0.011).toFixed(5)}&neLat=${(c.lat + 0.009).toFixed(5)}&neLng=${(c.lng + 0.011).toFixed(5)}`;
}

// 여정 하나 = 화면 흐름 하나. u: { token, index(회원 번호), i(이 테스트의 반복 번호) }
const JOURNEYS = {
  // 앱을 열어 홈에 3분 머문다: 알림 종, 지도 3번 움직임(카메라가 멈출 때마다), 목록, 현재 러너 수 1분마다
  home(s, u) {
    get('notification', '/api/v1/notifications/unread-count', u.token, 'unread');
    for (let k = 0; k < 3; k++) get('course', `/api/v1/courses/map?${viewport(pickOne(s.courses))}`, u.token, 'map');
    const c = pickOne(s.courses);
    const list = data(get('course', `/api/v1/courses?${viewport(c)}&sort=POPULAR&size=20`, u.token, 'list'));
    const ids = (list && list.content.length ? list.content : [{ courseId: c.id }]).map((x) => x.courseId);
    for (let k = 0; k < 3; k++) get('course', `/api/v1/courses/active-runners?${ids.map((id) => `courseIds=${id}`).join('&')}`, u.token, 'active-runners');
  },
  // 코스 상세(B1): 상세 · 저장 여부 · 랭킹 요약 · 랭킹 목록 · 리뷰 요약 · 내 리뷰 · 리뷰 목록
  detail(s, u) {
    const c = pickOne(s.courses);
    get('course', `/api/v1/courses/${c.id}`, u.token, 'detail');
    get('course', `/api/v1/courses/bookmarks/status?courseIds=${c.id}`, u.token, 'bookmark-status');
    get('ranking', `/api/v1/rankings/courses/${c.id}?period=ALL`, u.token, 'course-ranking');
    get('ranking', `/api/v1/rankings/courses/${c.id}/entries?period=ALL`, u.token, 'course-entries');
    get('review', `/api/v1/reviews/summary?courseId=${c.id}`, u.token, 'summary');
    get('review', `/api/v1/reviews/me?courseId=${c.id}`, u.token, 'mine');
    get('review', `/api/v1/reviews?courseId=${c.id}&sort=LATEST&excludeMine=true`, u.token, 'reviews');
  },
  // 러닝 1회: 코스 러닝(준비 · 시작 신호 · 구간 종료) 50% 또는 자유 러닝 30분 50%. 원본 500개씩 업로드 → 상태 확인.
  // 판정이 끝나 있으면 결과 · 구간 분석을 받는다(아니면 앱은 나중에 다시 확인한다)
  run(s, u) {
    const c = pickOne(s.courses);
    const id = Math.random() < 0.5 ? runSession(u.token, walk(c.route, 3), c.id) : runSession(u.token, walk(courseAnchors(50000 + u.i), 3, 1800));
    const st = data(get('run', `/api/v1/runs/sessions/${id}/status`, u.token, 'status'));
    if (st && st.processing === 'DONE') {
      get('run', `/api/v1/runs/records/${id}`, u.token, 'result');
      get('run', `/api/v1/runs/records/${id}/splits`, u.token, 'splits');
    }
  },
  // 코스 등록 하루 한도까지: 사용자 지정 1개(B3 → B5) + GPS 기록 기반 3개(B6: 기록 고르기 → 원본 경로 → 미리 보기 → 등록).
  // 회원마다 하루 한 번만 되므로 한 단계에서 회원을 한 번씩만 쓴다(ramp.py가 단계 사이에 한도를 되돌린다)
  register(s, u) {
    const name = `LT${TAG}r${RATE}u${u.index}`;
    get('course', '/api/v1/courses/registration-quota', u.token, 'quota');
    get('course', `/api/v1/courses/name-availability?name=${encodeURIComponent(name)}`, u.token, 'name');
    post('course', '/api/v1/courses', u.token, { anchorPoints: courseAnchors(40000 + u.index), name, difficulty: 'MEDIUM', tags: [] }, 'register-custom', { 'Idempotency-Key': uuid() });
    const recs = data(get('run', '/api/v1/runs/records?size=50', u.token, 'records'));
    const sources = (recs ? recs.content : []).filter((r) => !r.course && r.metrics.distanceM < 2000).slice(0, 3);
    sources.forEach((r, k) => {
      const src = data(get('run', `/api/v1/runs/records/${r.id}/course-source`, u.token, 'course-source'));
      if (!src) return;
      post('course', '/api/v1/courses/gps/route', u.token, { sourceRunRecordId: r.id, segments: src.segments }, 'gps-preview');
      post('course', '/api/v1/courses/gps', u.token, { sourceRunRecordId: r.id, segments: src.segments, name: `${name}g${k}`, difficulty: 'EASY', tags: [] }, 'register-gps', { 'Idempotency-Key': uuid() });
    });
  },
  // 랭킹 탭(E1): 누적 거리 요약 · 목록, 지역 주간 요약 · 목록, 다른 러너 프로필(I3)
  ranking(s, u) {
    const region = pickOne(REGIONS);
    get('ranking', '/api/v1/rankings/distance?period=ALL', u.token, 'distance');
    get('ranking', '/api/v1/rankings/distance/entries?period=ALL&cursor=0', u.token, 'distance-entries');
    get('ranking', `/api/v1/rankings/distance/regions/weekly?regionCode=${region}`, u.token, 'region-weekly');
    get('ranking', `/api/v1/rankings/distance/regions/weekly/entries?regionCode=${region}&cursor=0`, u.token, 'region-entries');
    const other = pickOne(s.memberIds);
    get('member', `/api/v1/members/${other}`, u.token, 'profile');
    get('ranking', `/api/v1/rankings/distance/members/${other}`, u.token, 'member-total');
  },
  // MY 탭(E3): 내 정보, 기록 목록, 등록한 코스 · 요약, 저장한 코스 요약, 알림 목록
  my(s, u) {
    get('member', '/api/v1/members/me', u.token, 'me');
    get('run', '/api/v1/runs/records?size=20', u.token, 'records');
    get('course', '/api/v1/courses/mine', u.token, 'my-courses');
    get('course', '/api/v1/courses/mine/summary', u.token, 'my-course-summary');
    get('course', '/api/v1/courses/bookmarks/summary', u.token, 'bookmark-summary');
    get('notification', '/api/v1/notifications', u.token, 'notifications');
  },
};
// 사용자 1명의 하루(가정): 러닝 1회, 코스 등록은 하루 한도까지, 나머지 화면은 한 번씩
const DAY = ['home', 'detail', 'run', 'register', 'ranking', 'my'];

export function journey(s) {
  const i = exec.scenario.iterationInTest;
  const index = i % s.tokens.length;
  const u = { token: s.tokens[index], index, i };
  for (const name of JOURNEY === 'day' ? DAY : JOURNEY === 'idle' ? [] : [JOURNEY]) {
    setJourney(name);
    JOURNEYS[name](s, u);
  }
  setJourney(null);
}

// 간섭 측정용: 모듈마다 가벼운 조회 하나씩
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
  const m = d.metrics;
  const http = m.http_req_duration.values;
  const out = {
    journey: JOURNEY, rate: RATE, duration: DURATION,
    iterations: m.iterations ? m.iterations.values.count : 0,
    dropped: m.dropped_iterations ? m.dropped_iterations.values.count : 0,
    total: { requests: http.count, p95: +http['p(95)'].toFixed(1), p99: +http['p(99)'].toFixed(1), max: +http.max.toFixed(1), failRate: +(m.http_req_failed.values.rate * 100).toFixed(2) },
    journeys: journeySummary(d), modules: moduleSummary(d),
  };
  const files = { stdout: JSON.stringify(out) + '\n', [`results/${TAG}.json`]: JSON.stringify(out, null, 1) };
  if (__ENV.SAVE) files['results/state.json'] = JSON.stringify(d.setup_data);
  return files;
}
