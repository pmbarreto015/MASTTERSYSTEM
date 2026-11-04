@echo off
setlocal EnableExtensions
title Gerador de Licenca MastterSystem

if exist "%~dp0gerador_licenca.exe" (
  "%~dp0gerador_licenca.exe"
  exit /b %errorlevel%
)

where dart.exe >nul 2>&1
if errorlevel 1 (
  echo ==========================================
  echo       GERADOR DE LICENCA MASTTERSYSTEM
  echo ==========================================
  echo.
  echo ERRO: o gerador nao foi encontrado e o Dart nao esta instalado.
  echo Coloque gerador_licenca.exe na mesma pasta deste arquivo.
  echo.
  pause
  exit /b 1
)

cd /d "%~dp0.."
dart run tool\generate_license.dart
if errorlevel 1 (
  echo.
  echo Nao foi possivel executar o gerador.
  pause
)

endlocal
