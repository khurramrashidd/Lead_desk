@echo off
REM ------------------------------------------------------------------
REM  deploy            AI brain (Cloud Functions) + Firestore rules
REM  deploy hosting    build the web app and publish it (web.app link)
REM  deploy all        both of the above, in that order
REM  Raises Firebase's 10-second load limit to 120 s (slow laptops).
REM ------------------------------------------------------------------
setlocal
set FUNCTIONS_DISCOVERY_TIMEOUT=120
cd /d "%~dp0"
if not exist functions\.env (
  echo [!] functions\.env is missing. Run:  copy functions\.env.example functions\.env  and add your Gemini key.
  exit /b 1
)
if /I "%~1"=="hosting" goto hosting

pushd functions
echo === Installing backend packages ===
call npm install --no-audit --no-fund
if errorlevel 1 (popd & exit /b 1)
echo === Running backend tests ===
call npm test
if errorlevel 1 (popd & echo [!] Tests failed - not deploying. & exit /b 1)
popd
echo === Deploying functions + Firestore rules ===
call firebase deploy --only functions,firestore --force
if errorlevel 1 (echo [!] Backend deploy reported an error - read the red lines above. & exit /b 1)
if /I not "%~1"=="all" exit /b 0

:hosting
echo === Building the web app ===
call flutter pub get
if errorlevel 1 exit /b 1
call flutter build web --release
if errorlevel 1 exit /b 1
echo === Publishing the web app ===
call firebase deploy --only hosting
exit /b
