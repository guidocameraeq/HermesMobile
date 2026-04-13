@echo off
echo ========================================
echo  Hermes Mobile - Publicar Release
echo ========================================
echo.

:: Leer version del pubspec.yaml
for /f "tokens=2 delims=: " %%a in ('findstr /b "version:" pubspec.yaml') do set VERSION=%%a
for /f "tokens=1 delims=+" %%a in ("%VERSION%") do set VER=%%a
set TAG=v%VER%

echo Version detectada: %TAG%
echo.

:: Confirmar
set /p CONFIRM="Publicar %TAG%? (S/N): "
if /i not "%CONFIRM%"=="S" (
    echo Cancelado.
    exit /b 0
)

:: Build
echo.
echo [1/4] Compilando APK...
set JAVA_HOME=C:\Program Files\Microsoft\jdk-17.0.18.8-hotspot
set ANDROID_HOME=C:\Android
set PATH=%JAVA_HOME%\bin;C:\tools\flutter\bin;%ANDROID_HOME%\cmdline-tools\latest\bin;%PATH%
call flutter build apk --release
if errorlevel 1 (
    echo ERROR: Build falló
    exit /b 1
)

:: Git
echo.
echo [2/4] Commit y push...
git add -A
git commit -m "release: %TAG%"
git push

:: Tag
echo.
echo [3/4] Creando tag %TAG%...
git tag -a %TAG% -m "Release %TAG%"
git push origin %TAG%

:: Release (requiere gh auth login)
echo.
echo [4/4] Creando release en GitHub...
echo NOTA: Si no tenés gh autenticado, creá el release manualmente en GitHub.
echo       Subí el APK de: build\app\outputs\flutter-apk\app-release.apk
echo.

echo ========================================
echo  Release %TAG% completado!
echo  APK: build\app\outputs\flutter-apk\app-release.apk
echo ========================================
pause
