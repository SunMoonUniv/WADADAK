# DB · 사진 백업

core DB와 run DB는 매일 `pg_dump`(custom 형식)로, 사진 저장소(RustFS 볼륨 `wadadak-server_photos`)는 매일 tar로 떠서 운영 PC(desktop-65isqe2)에 30일 보관하고, 매주 복원해 본다. 계획과 이유는 [운영 PC](<../운영 PC (감시 · 백업) - 2026-11-23.md>).

| 시각(KST) | PC | 스크립트 | 하는 일 |
| --- | --- | --- | --- |
| 매일 04:00 | core PC | `Backup-Db.ps1` | `wadadak-core-postgres-1`을 떠서 `C:\wadadak-backup\core-<날짜>.dump` → Taildrop으로 운영 PC. 최근 3개만 남김 |
| 매일 04:05 | run PC | `Backup-Db.ps1` | `wadadak-run-postgres-1`을 같은 방법으로 |
| 매일 04:10 | 인프라 PC | `Backup-Db.ps1` | `wadadak-server-storage-1`의 `/data`를 통째로 묶어 `C:\wadadak-backup\photos-<날짜>.tar` → 같은 방법으로 |
| 매일 04:30 | 운영 PC | `Receive-Backup.ps1` | `Downloads`의 덤프 · tar를 `C:\wadadak-backup\core` · `run` · `photos`로 옮기고 30일 지난 것을 지움. 그날 셋 중 하나라도 빠지면 Discord |
| 일요일 05:00 | 운영 PC | `Test-Restore.ps1` | 최근 덤프를 임시 컨테이너에 복원. 실패하거나 테이블 수가 다르면 Discord. 같은 날짜 사진 tar에 복원한 core DB가 가리키는 사진(리뷰 · 프로필)이 모두 없어도 Discord |

- 사진은 core DB보다 늦게 뜬다. 사진 키는 core DB에 있고, 키는 UUID라 덮어쓰지 않고 지우기만 한다. 그래서 같은 날짜 덤프와 tar를 함께 되돌리면 DB가 가리키는 사진이 모두 있다. 예외는 04:00~04:10에 지운 사진뿐이다. 그 사이 올라온 사진은 아무도 가리키지 않는 파일로 남는다(해는 없다).
- tar는 RustFS 데이터 폴더 그대로다(사진 · 버킷 공개 읽기 정책 · 설정). 같은 `rustfs/rustfs:1.0.1`에 되돌린다. RustFS 버전을 올리면 복원 절차를 다시 시험한다.
- 2026-11-23 사진은 2.5MB(6장)다. 매일 통째로 떠도 30일에 0.1GB가 안 된다. 하루 tar가 GB 단위가 되면 S3 증분 동기화(`mc mirror` 등)로 바꾼다.
- 덤프에는 회원 정보가, tar에는 프로필 사진이 있다. 운영 PC로만 보내고, 저장소 · Actions artifact(저장소가 공개라 누구나 받는다) · 채팅에 올리지 않는다. 운영 PC 계정은 팀 관리자만 쓴다.
- Discord 웹훅은 운영 PC의 `C:\wadadak-observability\ops\.env` 한 곳에만 있다. 서비스 PC의 백업 작업은 Discord로 보내지 않고, 빠진 날은 운영 PC가 찾는다.
- healthchecks.io: 복원 검사는 성공하면 핑, 실패하면 `/fail`을 보낸다. 작업이 아예 안 돌아 핑이 끊겨도 healthchecks.io가 알린다. 핑 주소는 운영 PC `C:\wadadak-observability\ops\.env`의 `HEALTHCHECKS_RESTORE_URL`이고, 없으면 핑만 건너뛴다. 남이 알면 가짜 신호를 보낼 수 있어 채팅에 붙이지 않는다.
- 서비스 PC의 결과는 `C:\wadadak-backup\backup.log`에 한 줄씩 남는다(`OK …` 또는 `FAIL …`).
- 작업은 로그인한 세션에서 돈다(Docker Desktop이 로그인해 있어야 도는 것과 같다). 자동 로그인이 꺼져 있으면 재부팅 뒤 돌지 않는다.

## 설치

### core PC · run PC

1. 이 폴더의 `Backup-Db.ps1`을 `C:\wadadak-backup\`에 복사한다. 러너 작업 폴더 밖이라 배포가 건드리지 않는다.
2. 한 번 손으로 돌린다. core PC 예:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\wadadak-backup\Backup-Db.ps1 -Container wadadak-core-postgres-1 -DbUser wadadak -Name core
   ```

   run PC는 `-Container wadadak-run-postgres-1 -DbUser wadadak_run -Name run`. 운영 PC `Downloads`에 덤프가 오면 된다.
3. 작업을 등록한다. core PC 예(run PC는 인자와 시각 04:05만 다르다):

   ```powershell
   $arg = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\wadadak-backup\Backup-Db.ps1 -Container wadadak-core-postgres-1 -DbUser wadadak -Name core'
   Register-ScheduledTask -TaskName 'WADADAK DB Backup' `
     -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg) `
     -Trigger (New-ScheduledTaskTrigger -Daily -At 04:00) `
     -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)) `
     -Principal (New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$env:USERNAME" -LogonType Interactive -RunLevel Limited)
   ```

### 인프라 PC

core PC와 같다. 인자는 `-Container wadadak-server-storage-1 -Name photos`(`-DbUser` 없음), 시각은 04:10, 작업 이름은 `WADADAK Photo Backup`. core DB 덤프(04:00)보다 늦어야 한다(위 시점 설명).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\wadadak-backup\Backup-Db.ps1 -Container wadadak-server-storage-1 -Name photos
```

### 운영 PC

1. `Receive-Backup.ps1` · `Test-Restore.ps1`을 `C:\wadadak-backup\`에 복사한다. 복원 검사용 이미지 `postgis/postgis:17-3.5`는 운영 PC 앞에서 받아 둔다(SSH로 받으면 자격 증명 도우미가 실패한다).
2. 서비스 PC 셋이 보낸 뒤 한 번씩 손으로 돌린다.

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\wadadak-backup\Receive-Backup.ps1
   ```

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\wadadak-backup\Test-Restore.ps1
   ```

   `OK …`가 나오면 된다. 알림이 가는지는 `Receive-Backup.ps1 -Date (Get-Date).AddDays(1)`로 한 번 본다(내일 덤프가 없어 Discord에 알림이 간다).
3. 작업 둘을 등록한다(위와 같은 방식). `Receive-Backup.ps1`은 `-Daily -At 04:30`, `Test-Restore.ps1`은 `-Weekly -DaysOfWeek Sunday -At 05:00`, 작업 이름은 `WADADAK Backup Receive` · `WADADAK Backup Restore Test`.

## 복원

### DB

운영 PC의 `C:\wadadak-backup\core\core-<날짜>.dump`를 그 DB가 있는 PC로 옮겨(Taildrop) 넣는다. 서비스를 멈추고 하는 일이라 팀에 알린 뒤 한다.

core PC 예:

```powershell
docker compose -p wadadak-core stop core
```

```powershell
docker cp $env:USERPROFILE\Downloads\core-<날짜>.dump wadadak-core-postgres-1:/tmp/restore.dump
```

```powershell
docker exec wadadak-core-postgres-1 pg_restore -U wadadak -d wadadak --clean --if-exists --no-owner /tmp/restore.dump
```

```powershell
docker compose -p wadadak-core start core
```

- `--clean`은 덤프에 있는 개체를 지우고 다시 만든다. 덤프 뒤에 쌓인 데이터는 사라진다.
- run DB는 `wadadak-run-postgres-1`, 계정 `wadadak_run`, 멈출 서비스는 `docker compose -p wadadak-run stop run`.
- core DB를 되돌리면 사진도 같은 날짜 tar로 함께 되돌린다. DB만 되돌리면 그 뒤에 지운 리뷰 · 프로필 사진이 저장소에 없어 깨진다.

### 사진

운영 PC의 `C:\wadadak-backup\photos\photos-<날짜>.tar`를 인프라 PC로 옮겨(Taildrop) 볼륨을 통째로 바꾼다. 멈춘 동안 앱의 사진 올리기 · 보기가 실패한다.

```powershell
docker compose -p wadadak-server stop storage
```

```powershell
docker run --rm -v wadadak-server_photos:/data -v "$env:USERPROFILE\Downloads:/backup:ro" --entrypoint sh rustfs/rustfs:1.0.1 -c 'find /data -mindepth 1 -delete && tar -xf /backup/photos-<날짜>.tar -C /data'
```

```powershell
docker compose -p wadadak-server start storage
```

- 볼륨에 있던 파일은 모두 지워진다. tar 뒤에 올라온 사진(최대 하루치)은 사라지고, 그 사진을 가리키는 리뷰 · 프로필은 이미지가 깨진다.
- 2026-11-23 시험: 이 명령으로 tar를 새 볼륨에 풀어 임시 RustFS를 띄웠다. 사진 4장의 md5가 운영 저장소와 같았고, 공개 읽기(키로 받기)는 되고 목록은 403이었다.
