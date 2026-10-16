@echo off
REM ------------------------------------------------------------------
REM  Deploy Firestore rules + Cloud Functions (the AI brain).
REM  On slow laptops Firebase gives the functions only 10 seconds to load
REM  during deploy ("User code failed to load ... Timeout after 10000").
REM  This raises it to 120 seconds.
REM  Usage:  deploy            (rules + functions)
REM          deploy hosting    (web app, after: flutter build web --release)
REM ------------------------------------------------------------------
set FUNCTIONS_DISCOVERY_TIMEOUT=120
if not exist functions\.env (
  echo [!] functions\.env is missing. Run:  copy functions\.env.example functions\.env  and add your Gemini key.
  exit /b 1
)
if /I "%~1"=="hosting" (
  call firebase deploy --only hosting
) else (
  call firebase deploy --only functions,firestore
)
