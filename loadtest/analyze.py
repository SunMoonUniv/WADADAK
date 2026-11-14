"""측정 결과를 모듈별로 묶는다.

  python analyze.py cpu <jfr 파일>   → CPU 샘플을 모듈별로(스택에서 가장 가까운 com.wadadak.<모듈> 프레임 기준)
  python analyze.py db  <csv 파일>   → pg_stat_statements 실행 시간을 스키마(= 모듈)별로

JFR 파일은 `jfr print --events jdk.ExecutionSample --stack-depth 128`로 읽는다(JAVA_HOME/bin/jfr).
"""
import csv
import os
import re
import subprocess
import sys
from collections import Counter

MODULES = ["member", "course", "run", "ranking", "review", "notification"]
FRAME = re.compile(r"^\s+com\.wadadak\.(\w+)\.")


def cpu(path):
    jfr = os.path.join(os.environ.get("JAVA_HOME", r"C:\Program Files\Java\jdk-21.0.11"), "bin", "jfr")
    out = subprocess.run([jfr, "print", "--events", "jdk.ExecutionSample", "--stack-depth", "128", path],
                         capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
    counts = Counter()
    for event in out.split("jdk.ExecutionSample")[1:]:
        found = [m.group(1) for line in event.splitlines() if (m := FRAME.match(line))]
        # 스택 위(실행 중)에서 아래로: 처음 만나는 업무 모듈. 업무 모듈이 없고 common만 있으면 common(필터 · 보안 · 응답)
        module = next((f for f in found if f in MODULES), "common" if found else "framework")
        counts[module] += 1
    report(counts, "CPU 샘플")


def db(path):
    total = Counter()
    with open(path, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            q, ms = row["query"].lower(), float(row["total_exec_time"])
            hits = [m for m in MODULES + ["common"] if re.search(rf"\b{m}\.", q)]
            total[hits[0] if len(hits) == 1 else ("+".join(hits) if hits else "other")] += ms
    report(total, "DB 실행 시간(ms)")


def report(counts, label):
    s = sum(counts.values()) or 1
    print(f"{label} 합계 {s:.0f}")
    for k, v in counts.most_common():
        print(f"  {k:<14}{v:>12.0f}  {100 * v / s:5.1f}%")


if __name__ == "__main__":
    {"cpu": cpu, "db": db}[sys.argv[1]](sys.argv[2])
