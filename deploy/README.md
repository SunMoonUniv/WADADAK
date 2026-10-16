# 공용 서버 (배포)

실기기에서 실제 소셜 로그인으로 시험하는 팀 공용 서버다. 서버 PC 한 대에서 Docker로 띄우고, 포트포워딩 없이 Cloudflare 터널로 `https://api.leedohyunn8n.shop`(서버)과 `https://files.leedohyunn8n.shop`(사진)에 연다. main에 머지되면 자동으로 배포된다.

```
PR ─► CI (GitHub 서버) ─► 승인 · 머지
main push ─► backend.yml
               backend  (ubuntu-latest)          테스트
               deploy   (서버 PC self-hosted 러너) 이미지 빌드 → compose up --wait
                        비밀값은 GitHub 환경 wadadak-server의 Secrets에서 받는다

서버 PC (Docker Desktop) · compose 프로젝트 wadadak-server
   postgres · storage(RustFS) · backend · cloudflared ──► Cloudflare ◄── 폰 https://api.leedohyunn8n.shop
   (포트를 열지 않는다)                                        └──────── 사진 https://files.leedohyunn8n.shop
```

- 주소: `https://api.leedohyunn8n.shop` · 상태 [`/actuator/health`](https://api.leedohyunn8n.shop/actuator/health) · Swagger [`/swagger-ui.html`](https://api.leedohyunn8n.shop/swagger-ui.html)
- 비밀값(DB 비밀번호 · JWT 키 · 사진 저장소 비밀번호 · 터널 토큰)은 GitHub Secrets에만 둔다. 서버 PC에는 비밀값 파일이 없다.
- `prod` 프로필로 뜬다(`compose.yaml`의 `SPRING_PROFILES_ACTIVE`). 스텁(`app.stub.*: true`)이나 가짜 소셜 검증이 켜져 있으면 `StubGuard`가 기동을 막는다. 소셜 로그인은 실제 검증이다.
- 사진 저장소는 S3 호환 RustFS다(개발 정책 7장 사진 업로드). 앱이 업로드 폼으로 직접 올리고, 사진은 로그인 없이 받는다(객체 받기만 허용, 목록은 막음). 버킷 `wadadak`과 공개 읽기 설정은 첫 업로드 때 서버가 만든다.
- 서버 DB는 개발용 DB(`BackEnd/compose.yaml`, 5433)와 따로다. 서버 PC에서 개발해도 서로 겹치지 않는다.
- Swagger(`/swagger-ui.html`)도 인터넷에 열린다. 막으려면 Cloudflare Access로 `/swagger-ui*` · `/v3/api-docs*`에 팀원 이메일 인증을 건다.

## 보안 — 저장소가 공개라 꼭 지킨다

self-hosted 러너는 PR 워크플로도 받는다. PR에서는 PR 작성자의 워크플로 파일이 쓰인다. 포크 PR이 `runs-on`을 이 러너로 바꾸면 **머지 전에** 서버 PC에서 그 코드가 돈다.

1. 저장소 Settings → Actions → General → Fork pull request workflows → **Require approval for all external contributors**
2. 외부 PR의 워크플로 실행을 승인하기 전에 `.github/workflows/` 변경을 본다. 바뀌었으면 승인하지 않는다.
3. main 보호: PR 필수, 승인 1명, 필수 체크 `backend` · `frontend` (개발 정책 10.4)
4. 환경 `wadadak-server`의 배포 브랜치를 `main`으로 묶는다(아래 3번). 다른 브랜치 · PR 워크플로는 Secrets를 읽지 못한다.
5. 배포 작업은 main push와 수동 실행에서만 돈다(`backend.yml` deploy의 `if`). 이 조건을 지우지 않는다.

## 서버 PC 준비 (한 번)

### 1. PC 설정
- Docker Desktop은 Windows에 로그인해 있어야 돈다.
  - Docker Desktop Settings → General → **Start Docker Desktop when you sign in**
  - 절전 안 함(전원 옵션), 재부팅 후 자동 로그인, Windows 업데이트 사용 시간 설정
- 로그인 계정이 `docker-users` 그룹에 있어야 한다. 러너가 이 계정으로 Docker를 쓴다.
- 서버 PC의 Docker에서는 `docker inspect`로 비밀값(환경 변수)이 보인다. 서버 PC 계정은 팀 관리자만 쓴다.

### 2. GitHub 러너
보안 1번(포크 PR 승인)을 먼저 한다. 러너가 켜지는 순간부터 PR 워크플로를 받는다.

**관리자 PowerShell**에서 한다. 관리자 PowerShell은 `C:\Windows\System32`에서 시작하므로 GitHub 안내 명령보다 `cd`를 먼저 한다(그대로 붙이면 시스템 폴더에 설치된다).

```powershell
mkdir C:\actions-runner-wadadak; cd C:\actions-runner-wadadak
# Settings → Actions → Runners → New self-hosted runner → Windows x64의 Download 명령으로 zip을 받아 푼다
.\config.cmd --url https://github.com/SunMoonUniv/WADADAK --token <등록 토큰> --labels wadadak-server
```

- 나머지 질문은 Enter. 서비스로 돌릴지 물으면 `N`.
- 러너는 서비스가 아니라 **로그인할 때 작업 스케줄러가 켠다**. 서버 PC 계정에 비밀번호가 없어 서비스로 돌릴 수 없고(Windows는 비밀번호 없는 계정의 서비스 로그온을 막는다), Docker Desktop도 어차피 로그인해 있어야 돈다. 관리자 권한 없이 일반 권한으로 돈다.
  ```powershell
  $dir = 'C:\actions-runner-wadadak'; $user = "$env:COMPUTERNAME\$env:USERNAME"
  Register-ScheduledTask -TaskName 'WADADAK GitHub Runner' `
    -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -Command `"& '$dir\run.cmd'`"" -WorkingDirectory $dir) `
    -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $user) `
    -Settings (New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -StartWhenAvailable) `
    -Principal (New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited)
  Start-ScheduledTask -TaskName 'WADADAK GitHub Runner'
  ```
- 끄기 · 켜기: `Stop-ScheduledTask` · `Start-ScheduledTask -TaskName 'WADADAK GitHub Runner'`. 창이 숨겨져 있어 실수로 닫히지 않는다. 로그는 `C:\actions-runner-wadadak\_diag`.
- 확인: GitHub 러너 목록에 `wadadak-server` 라벨로 Idle(초록)

### 3. GitHub 환경과 Secrets
저장소 Settings → Environments → New environment `wadadak-server`

- Deployment branches and tags → **Selected branches and tags** → `main`
- Environment secrets:

| 이름 | 값 |
| --- | --- |
| `DB_PASSWORD` | 무작위 문자열(`openssl rand -hex 24`). 첫 배포 때 DB가 이 값으로 만들어진다. 나중에 바꾸면 DB와 어긋나므로 DB 초기화(아래 운영 표)와 함께 바꾼다 |
| `JWT_PRIVATE_KEY` | 개인키 PEM을 base64 한 줄로(아래 명령) |
| `JWT_PUBLIC_KEY` | 공개키 PEM을 base64 한 줄로(아래 명령) |
| `STORAGE_SECRET_KEY` | 사진 저장소 비밀번호. 무작위 문자열(`openssl rand -hex 24`). 저장소와 서버가 같이 받는다. 바꾸면 저장소 계정도 바뀐다 |
| `TUNNEL_TOKEN` | Cloudflare 터널 토큰(5번). 없으면 터널 없이 뜬다 |

JWT 키 만들기(Git Bash). 출력한 두 줄을 Secrets에 넣고 파일은 지운다:

```sh
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out private.pem
openssl pkey -in private.pem -pubout -out public.pem
base64 -w0 private.pem; echo   # → JWT_PRIVATE_KEY
base64 -w0 public.pem; echo    # → JWT_PUBLIC_KEY
rm private.pem public.pem
```

- 값은 줄바꿈 없는 한 줄이다. 앞뒤에 공백 · 줄바꿈이 붙으면 서버가 키를 읽지 못한다.
- 서버는 `JWT_*_KEY_LOCATION=base64:…`로 키를 받는다(Spring Boot의 `base64:` 리소스). 파일을 두지 않는다.
- 로컬 개발 키(`BackEnd/.local/jwt`)와 다른 키를 쓴다. 같은 키면 로컬 서버(가짜 소셜 로그인)가 발급한 토큰이 공용 서버에서도 통한다.
- Secrets는 배포할 때만 서버로 간다. 값을 바꾸면 수동 배포를 한 번 돌린다.
- JWT 키를 바꾸면 발급한 토큰이 모두 무효가 되어 모든 기기에서 다시 로그인해야 한다.

### 4. 첫 배포
Actions → Backend CI → Run workflow(main). deploy 작업이 통과하면 서버가 떠 있다. 터널을 붙이기 전에는 서버 PC 안에서만 보인다(`docker compose -p wadadak-server ps`가 healthy).

### 5. Cloudflare 터널
1. 도메인을 Cloudflare에 추가하고 상태가 **Active**가 될 때까지 기다린다(등록 업체에서 네임서버를 Cloudflare 것으로 바꾼다. Cloudflare에서 산 도메인은 바로 Active).
2. Networking → Tunnels → **Create a tunnel**, 이름 `wadadak-server`, 환경은 Docker
3. 설치 안내 명령의 `--token` 뒤 문자열을 Secrets의 `TUNNEL_TOKEN`에 넣는다. 설치 명령은 실행하지 않는다(compose의 cloudflared가 띄운다).
4. 수동 배포를 돌린다. cloudflared가 Cloudflare에 연결돼야 배포가 통과한다(토큰이 틀리면 실패). 터널 화면에 커넥터가 연결됨으로 보인다.
5. 터널 → **Routes** 탭 → Add route → **Published application**
   - Subdomain `api`, Domain `leedohyunn8n.shop`, Service URL `http://backend:8080`
   - `localhost`가 아니다. cloudflared 컨테이너에서 backend는 compose 서비스 이름으로 보인다.
   - DNS 레코드(`api` CNAME → `<터널 ID>.cfargotunnel.com`, 프록시됨)는 Cloudflare가 자동으로 만든다. 같은 이름의 레코드가 이미 있으면 지우고 다시 추가한다.
   - 한 단계 하위 도메인으로 둔다. Cloudflare 기본 인증서는 `a.b.leedohyunn8n.shop`을 덮지 않는다.
   - 사진도 같은 방법으로 하나 더 추가한다: Subdomain `files`, Service URL `http://storage:9000`
6. `https://api.leedohyunn8n.shop/actuator/health`가 `{"status":"UP"}`, `https://files.leedohyunn8n.shop/health`가 `"status":"ok"`이면 끝. 오류 1033은 터널이 연결되지 않은 것(cloudflared가 꺼짐), 502는 Service URL이 틀렸거나 backend가 꺼진 것이다.

## 운영

| 할 일 | 방법 |
| --- | --- |
| 배포 | main 머지. 수동으로는 Actions → Backend CI → Run workflow(main) |
| 되돌리기 | 문제 PR을 revert PR로 머지한다 |
| 비밀값 바꾸기 | 환경 `wadadak-server`의 Secrets 수정 → 수동 배포 |
| 상태 · 로그 | `docker compose -p wadadak-server ps` · `docker logs -f wadadak-server-backend-1` |
| 요청 로그 | `docker logs -f wadadak-server-backend-1 2>&1 \| grep RequestLogFilter` — 한 줄에 메서드 · 경로 · 상태 · 처리 시간 · IP. `/actuator`는 빠진다 |
| DB 접속 | `docker exec -it wadadak-server-postgres-1 psql -U wadadak` |
| DB 초기화 (데이터 전부 삭제) | `docker compose -p wadadak-server down` → `docker volume rm wadadak-server_db` → 수동 배포 |
| 사진 저장소 로그 | `docker logs -f wadadak-server-storage-1`. 사진 파일은 볼륨 `wadadak-server_photos`에 있다. DB를 초기화하면 사진도 같이 지운다(`docker volume rm wadadak-server_photos`) |

## 앱 연결

```bash
flutter run --dart-define=API_BASE_URL=https://api.leedohyunn8n.shop
```

- 카카오 로그인은 팀 공용 `debug.keystore`로 서명한 빌드에서만 된다([FrontEnd README](../FrontEnd/README.md)).
- 카카오 · Google 콘솔은 서버 주소와 관계없다. 서버를 옮겨도 고칠 것이 없다.
