# DB 백업

core DB와 run DB를 매일 `pg_dump`(custom 형식)로 떠서 운영 PC(desktop-65isqe2)에 30일 보관하고, 매주 복원해 본다. 계획과 이유는 [운영 PC](<../운영 PC (감시 · 백업) - 2026-11-23.md>).

| 시각(KST) | PC | 스크립트 | 하는 일 |
| --- | --- | --- | --- |
| 매일 04:00 | core PC | `Backup-Db.ps1` | `wadadak-core-postgres-1`을 떠서 `C:\wadadak-backup\core-<날짜>.dump` → Taildrop으로 운영 PC. 최근 3개만 남김 |
| 매일 04:05 | run PC | `Backup-Db.ps1` | `wadadak-run-postgres-1`을 같은 방법으로 |
| 매일 04:30 | 운영 PC | `Receive-Backup.ps1` | `Downloads`의 덤프를 `C:\wadadak-backup\core` · `run`으로 옮기고 30일 지난 것을 지움. 그날 덤프가 빠지면 Discord |
| 일요일 05:00 | 운영 PC | `Test-Restore.ps1` | 최근 덤프를 임시 컨테이너에 복원. 실패하거나 테이블 수가 다르면 Discord |

- 덤프에는 회원 정보가 있다. 운영 PC로만 보내고, 저장소 · Actions artifact(저장소가 공개라 누구나 받는다) · 채팅에 올리지 않는다. 운영 PC 계정은 팀 관리자만 쓴다.
- Discord 웹훅은 운영 PC의 `C:\wadadak-observability\ops\.env` 한 곳에만 있다. 서비스 PC의 백업 작업은 알림을 보내지 않고, 빠진 날은 운영 PC가 찾는다.
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

### 운영 PC

1. `Receive-Backup.ps1` · `Test-Restore.ps1`을 `C:\wadadak-backup\`에 복사한다. 복원 검사용 이미지 `postgis/postgis:17-3.5`는 운영 PC 앞에서 받아 둔다(SSH로 받으면 자격 증명 도우미가 실패한다).
2. 서비스 PC 둘이 보낸 뒤 한 번씩 손으로 돌린다.

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\wadadak-backup\Receive-Backup.ps1
   ```

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\wadadak-backup\Test-Restore.ps1
   ```

   `OK …`가 나오면 된다. 알림이 가는지는 `Receive-Backup.ps1 -Date (Get-Date).AddDays(1)`로 한 번 본다(내일 덤프가 없어 Discord에 알림이 간다).
3. 작업 둘을 등록한다(위와 같은 방식). `Receive-Backup.ps1`은 `-Daily -At 04:30`, `Test-Restore.ps1`은 `-Weekly -DaysOfWeek Sunday -At 05:00`, 작업 이름은 `WADADAK Backup Receive` · `WADADAK Backup Restore Test`.

## 복원

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
