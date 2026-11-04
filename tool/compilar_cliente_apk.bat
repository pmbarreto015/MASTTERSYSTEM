@echo off
setlocal EnableExtensions
title Compilar Cliente APK com Licenciamento
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0compilar_licencas.ps1" -Alvo Android
set "BUILD_EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%BUILD_EXIT_CODE%"=="0" echo ERRO: confira as mensagens acima.
pause
exit /b %BUILD_EXIT_CODE%
