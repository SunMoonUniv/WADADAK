"""여정 하나의 부하를 단계별로 올리며 어디서 느려지는지 찾는다.

  python ramp.py seed                                 # 시드: 회원 · 코스 → 기록(판정 대기) → 리뷰
  python ramp.py <여정> <초당 여정 수, 쉼표로> [--split] [--probe] [--duration 40]
  예) python ramp.py home 10,20,40,80,160
      python ramp.py day 1,2,3,4,6,8 --split      # run 요청만 8091 인스턴스로(같은 DB)

단계마다 results/<여정>[-split]-<속도>.json, 전체는 results/ramp-<여정>[-split].jsonl에 남긴다.
서버(8090, 분리 실험이면 8091도) · 부하 DB 컨테이너(wadadak-loadtest-db)가 떠 있어야 한다.
"""
import argparse
import json
import os
import subprocess
import sys
import threading
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
POOL = 600  # 시드 회원 수. 코스 등록은 회원마다 하루 한 번이라 한 단계에 이 수까지만 쓴다
PSQL = ["docker", "exec", "-i", "wadadak-loadtest-db", "psql", "-U", "wadadak", "-d", "wadadak", "-Atq"]

# 부하 테스트가 등록한 코스(이름 LT…)를 지우고 하루 등록 한도를 되돌린다. 시드 코스는 그대로 둔다
RESET = """
create temp table lt as select id from course.courses where name like 'LT%';
delete from run.gps_source_links where course_id in (select id from lt);
delete from run.gps_course_status_copies where course_id in (select id from lt);
delete from course.registration_requests where course_id in (select id from lt);
delete from course.gps_course_sources where course_id in (select id from lt);
delete from course.course_completions where course_id in (select id from lt);
delete from course.completion_elevation_profiles where course_id in (select id from lt);
delete from course.course_stats where course_id in (select id from lt);
delete from course.course_daily_stats where course_id in (select id from lt);
delete from course.course_active_runners where course_id in (select id from lt);
delete from course.course_bookmarks where course_id in (select id from lt);
delete from course.courses where id in (select id from lt);
delete from course.daily_registration_counts;
"""


def sql(text):
    return subprocess.run(PSQL, input=text, capture_output=True, text=True, encoding="utf-8").stdout.strip()


def backlog():
    return int(sql("select count(*) from run.sessions where processing='PROCESSING'") or 0)


def k6(env, script="load.js"):
    cmd = ["docker", "run", "--rm", "-v", f"{HERE}:/lt", "-w", "/lt"]
    for k, v in env.items():
        cmd += ["-e", f"{k}={v}"]
    cmd += ["grafana/k6:1.0.0", "run", "--quiet", script]
    subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")


def wait_judged():
    """업로드한 기록의 판정이 끝날 때까지 기다린다. (끝났을 때 밀려 있던 수, 걸린 초)"""
    left, t0 = backlog(), time.time()
    while backlog() > 0:
        time.sleep(2)
    return left, round(time.time() - t0)


def seed():
    for phase in ("courses", "runs", "reviews"):
        print(f"시드 {phase} …", flush=True)
        k6({"SEED": 1, "PHASE": phase, "N": POOL}, "seed.js")
        left, seconds = wait_judged()
        if left:
            print(f"  기록 판정 {left}건 대기 {seconds}초")
    print(sql("select 'members='||(select count(*) from member.members)||' courses='||(select count(*) from course.courses)"
              "||' records='||(select count(*) from run.records)||' reviews='||(select count(*) from review.reviews)"))


class HostCpu(threading.Thread):
    """부하를 거는 동안 PC 전체 CPU 사용률(서버 JVM이 보는 system.cpu.usage)을 2초마다 잰다.
    90%를 넘으면 그 단계는 서버가 아니라 PC가 한계였을 수 있다(부하 발생기 · DB가 같은 PC에 있을 때)."""

    def __init__(self):
        super().__init__(daemon=True)
        token = json.load(open(os.path.join(HERE, "results", "state.json"), encoding="utf-8"))["tokens"][0]
        self.request = urllib.request.Request("http://localhost:8090/actuator/metrics/system.cpu.usage",
                                              headers={"Authorization": f"Bearer {token}"})
        self.samples, self.running = [], True

    def run(self):
        while self.running:
            try:
                with urllib.request.urlopen(self.request, timeout=2) as res:
                    self.samples.append(json.load(res)["measurements"][0]["value"] * 100)
            except Exception:
                pass  # 과부하로 응답이 없으면 그 순간은 건너뛴다
            time.sleep(2)

    def stop(self):
        self.running = False
        return round(sum(self.samples) / len(self.samples)) if self.samples else -1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("journey")
    ap.add_argument("rates", nargs="?")
    ap.add_argument("--split", action="store_true", help="run 요청만 8091 인스턴스로")
    ap.add_argument("--probe", action="store_true", help="모든 모듈 탐침을 함께 돌린다")
    ap.add_argument("--duration", type=int, default=40)
    a = ap.parse_args()
    if a.journey == "seed":
        return seed()
    name = a.journey + ("-split" if a.split else "")
    os.makedirs(os.path.join(HERE, "results"), exist_ok=True)

    k6({"SAVE": 1, "JOURNEY": "idle", "DURATION": "1s", "TAG": "save"})  # 토큰 · 코스 목록(토큰은 1시간)
    log = open(os.path.join(HERE, "results", f"ramp-{name}.jsonl"), "w", encoding="utf-8")
    print(f"{'속도':>5} {'여정':>6} {'누락':>5} {'요청':>7} {'p95':>8} {'p99':>8} {'실패%':>6} {'판정대기':>7} {'밀린 수':>6} {'PC CPU':>6}  여정별 p95")
    for rate in [float(r) for r in a.rates.split(",")]:
        rate = int(rate) if rate == int(rate) else rate
        if a.journey in ("register", "day"):
            if rate * a.duration > POOL:
                print(f"{rate}: 한 단계에 회원 {POOL}명을 넘어 건너뜀")
                continue
            sql(RESET)
        tag = f"{name}-{rate}"
        env = {"JOURNEY": a.journey, "RATE": rate, "DURATION": f"{a.duration}s", "TAG": tag}
        if a.split:
            env["RUN_BASE"] = "http://host.docker.internal:8091"
        if a.probe:
            env["PROBE"] = 1
        cpu = HostCpu()
        cpu.start()
        k6(env)
        host = cpu.stop()
        left, drain = wait_judged()
        try:
            r = json.load(open(os.path.join(HERE, "results", f"{tag}.json"), encoding="utf-8"))
        except FileNotFoundError:
            print(f"{rate}: k6 결과 없음")
            break
        r.update(backlog=left, drainSeconds=drain, hostCpu=host)
        log.write(json.dumps(r, ensure_ascii=False) + "\n")
        log.flush()
        t = r["total"]
        parts = " ".join(f"{j}={v['p95']:.0f}" for j, v in r["journeys"].items())
        print(f"{rate:>5} {r['iterations']:>6} {r['dropped']:>5} {t['requests']:>7} {t['p95']:>8.1f} {t['p99']:>8.1f} {t['failRate']:>6.2f} {drain:>6}s {left:>6} {host:>5}%  {parts}", flush=True)
        # 한계를 한참 넘으면 더 올려도 얻는 것이 없다
        if t["failRate"] >= 5 or t["p95"] >= 5000 or r["dropped"] > r["iterations"]:
            print("한계를 넘어 멈춤")
            break
    if a.journey in ("register", "day"):
        sql(RESET)


if __name__ == "__main__":
    sys.exit(main())
