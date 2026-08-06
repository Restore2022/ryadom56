@echo off
set JAVA_HOME=E:\android\jbr
set ANDROID_HOME=E:\sdk
set ANDROID_SDK_ROOT=E:\sdk
set PATH=E:\flutter\bin;E:\sdk\platform-tools;%JAVA_HOME%\bin;%PATH%
set PUB_CACHE=E:\pub-cache
cd /d E:\cursorproject\newprojct\mobile
if exist build rmdir /s /q build
if exist android\.gradle rmdir /s /q android\.gradle
if exist .dart_tool rmdir /s /q .dart_tool
flutter pub get
flutter build apk --debug
echo EXIT=%ERRORLEVEL%
if exist build\app\outputs\flutter-apk\app-debug.apk (
  echo APK_OK
  dir build\app\outputs\flutter-apk\app-debug.apk
)
