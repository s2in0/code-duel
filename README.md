# 코드 듀얼

코딩 문제를 풀어 기술을 쓰는 1:1 알고리즘 배틀 게임입니다. 학생은 학번으로 들어와 픽셀 파트너와 함께 랭크를 올리고, 교사는 교사 계정으로 들어와 문제와 수업 설정을 관리합니다.

- 게임 화면: `index.html` (GitHub Pages로 배포)
- 기록 저장: [Supabase](https://supabase.com) (학생 점수·전적·파트너, 교사가 만든 문제, 수업 설정)
- `code-duel.html`: 서버 없이 한 브라우저에서만 돌아가는 시제품 버전

## 처음 설정하기

### 1. Supabase 프로젝트 만들기
1. supabase.com 에 가입하고 새 프로젝트를 만듭니다. 지역은 Northeast Asia (Seoul)을 고르세요.
2. **SQL Editor**에서 `supabase/schema.sql` 내용을 붙여 넣고 Run 합니다.
3. **Authentication > Users > Add user**에서 교사 계정(이메일, 비밀번호)을 만듭니다. *Auto Confirm User*를 켜세요.
4. SQL Editor에서 그 이메일을 교사로 등록합니다.
   ```sql
   insert into public.teachers (email) values ('교사이메일@학교.kr');
   ```
5. **Authentication > Sign In / Providers > Email**에서 *Allow new users to sign up*을 끕니다. 아무나 교사 계정을 만들지 못하게 하기 위해서입니다.

### 2. config.js 채우기
**Project Settings > API**에서 Project URL과 anon(publishable) 키를 복사해 `config.js`에 넣습니다. anon 키는 브라우저에 공개돼도 되는 키입니다. `service_role` 키는 절대 넣지 마세요.

### 3. GitHub Pages
저장소 **Settings > Pages**에서 *Deploy from a branch*, `main` 브랜치의 `/ (root)`를 고르면 `https://<계정>.github.io/<저장소>/` 링크가 생깁니다.

## 수업에서 쓰기
- 교사: 링크 → 교사 탭 → 이메일·비밀번호로 로그인 → 수업 설정에서 **학급 입장 코드**를 만들고 학생들에게 알려 줍니다.
- 학생: 링크 → 학번과 입장 코드 입력 → 처음이면 파트너 선택 → 매칭 시작.
- 입장 코드를 비워 두면 학번만으로 들어올 수 있습니다. 다른 학생 학번으로 들어오는 걸 막으려면 수업마다 코드를 바꾸세요.

## 알아 둘 점 (시제품 단계)
- 상대는 아직 컴퓨터(연습 상대)입니다. 학생끼리 실시간 대전은 다음 단계입니다.
- 문제 정답이 브라우저 코드 안에 있어서, 개발자 도구를 열면 볼 수 있습니다. 서버 채점은 설계 문서의 다음 단계입니다.
- 경기 결과는 브라우저가 보내고 점수 계산은 서버가 합니다. 결과 자체를 꾸며 보내는 것까지는 막지 못합니다.
- 랭킹을 보여 주기 위해 학번·닉네임·점수는 링크를 가진 누구나 읽을 수 있습니다.
