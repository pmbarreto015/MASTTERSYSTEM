@echo off
setlocal EnableExtensions
title Compilar Administrador de Licencas
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0compilar_licencas.ps1" -Alvo Servidor
set "BUILD_EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%BUILD_EXIT_CODE%"=="0" echo ERRO: confira as mensagens acima.
pause
exit /b %BUILD_EXIT_CODE%