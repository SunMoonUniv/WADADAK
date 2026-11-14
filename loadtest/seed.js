// 시드: PHASE=courses → 회원 N명 가입 · 1명당 사용자 지정 코스 1개
//       PHASE=runs    → 1명당 코스 러닝 1번 · 자유 러닝 30분 1번 · GPS 코스 등록 원본용 짧은 자유 러닝 3번(7분, 약 1.3km)
//       PHASE=reviews → 1명당 완주한 코스에 리뷰 · 저장 코스 2개
import { sleep } from 'k6';
import exec from 'k6/execution';
import { login, post, put, get, data, courseAnchors, walk, runSession, AREA, uuid } from './lib.js';

const N = +(__ENV.N || 600);
const PHASE = __ENV.PHASE || 'courses';

export const options = {
  scenarios: { seed: { executor: 'shared-iterations', vus: 20, iterations: N, maxDuration: '60m' } },
  summaryTrendStats: ['avg', 'p(95)', 'max', 'count'],
};

export function setup() {
  if (PHASE === 'courses') return {};
  const token = login(0);
  const courses = [];
  let cursor = '';
  do {
    const q = `swLat=${AREA.swLat}&swLng=${AREA.swLng}&neLat=${AREA.neLat}&neLng=${AREA.neLng}&sort=LATEST&size=50${cursor ? `&cursor=${cursor}` : ''}`;
    const d = data(get('course', `/api/v1/courses?${q}`, token, 'course-list'));
    d.content.forEach((c) => courses.push({ id: c.courseId, route: c.route }));
    cursor = d.nextCursor;
  } while (cursor);
  return { courses };
}

export default function (s) {
  const i = exec.scenario.iterationInTest;
  const token = login(i);
  if (PHASE === 'courses') {
    post('course', '/api/v1/courses', token, { anchorPoints: courseAnchors(i), name: `부하코스${i}`, difficulty: 'MEDIUM', tags: [] }, 'course-register', { 'Idempotency-Key': uuid() });
    return;
  }
  const pick = (k) => s.courses[(i * 7 + k * 13) % s.courses.length];
  if (PHASE === 'runs') {
    const c = pick(0);
    runSession(token, walk(c.route, 3), c.id);
    runSession(token, walk(courseAnchors(i + 1000), 3, 1800));
    // GPS 코스 등록 원본: 회원마다 서로 다른 곳(다른 코스와 85% 넘게 겹치지 않게)
    for (let k = 0; k < 3; k++) runSession(token, walk(courseAnchors(20000 + i * 3 + k), 3, 420));
    return;
  }
  // reviews: 업로드한 코스 기록은 서버가 비동기로 판정한다. 기록 목록에서 완주 기록을 찾아 리뷰를 쓴다
  const recs = data(get('run', '/api/v1/runs/records?size=20', token, 'records')).content;
  const done = recs.find((r) => r.course && r.course.reviewEligible);
  if (done) {
    post('review', '/api/v1/reviews', token, {
      courseId: done.course.courseId, sourceRunRecordId: done.id, rating: 1 + (i % 5), safetyRating: 4, roadRating: 4,
      lightingRating: 3, amenityRating: 3, content: '부하 테스트 리뷰입니다', tags: [], photoKeys: [],
    }, 'review-write');
  }
  for (let k = 0; k < 2; k++) put('course', `/api/v1/courses/bookmarks/${pick(k + 5).id}`, token, undefined, 'bookmark');
  sleep(0.1);
}
