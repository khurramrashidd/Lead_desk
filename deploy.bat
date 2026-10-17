@echo off
REM ------------------------------------------------------------------
REM  deploy            AI brain (Cloud Functions) + Firestore rules
REM  deploy hosting    build the web app and publish it (web.app link)
REM  Raises Firebase's 10-second load limit to 120 s (slow laptops).
REM ------------------------------------------------------------------
set FUNCTIONS_DISCOVERY_TIMEOUT=120
if not exist functions\.env (
  echo [!] functions\.env is missing. Run:  copy functions\.env.example functions\.env  and add your Gemini key.
  exit /b 1
)
if /I "%~1"=="hosting" (
  call flutter build web --release || exit /b 1
  call firebase deploy --only hosting
  exit /b
)
call npm --prefix functions install --no-audit --no-fund || exit /b 1
call npm --prefix functions test || exit /b 1
call firebase deploy --only functions,firestore --force
