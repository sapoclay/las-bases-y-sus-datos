@echo off
:: Solicitar permisos de administrador automaticamente
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Para que esto funcione debes de ser el administrador.Solicitando permisos de administrador...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

title Las bases y sus datos
color 0A
cd /d "%~dp0"

powershell -ExecutionPolicy Bypass -File "%~dp0gestor_bbdd.ps1"
pause