@echo off
rem Doble clic: prepara y levanta la arquitectura completa de Reserva Viva en este equipo.
rem Acepta los mismos argumentos que levantar-sistema.ps1 (por ejemplo: levantar-sistema.cmd estado).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0levantar-sistema.ps1" %*
set RC=%ERRORLEVEL%
echo.
pause
exit /b %RC%
