@echo off
setlocal
"%~dp0tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "%~dp0game" --log-file "%~dp0output\prototype\selftest.log" -- --self-test
set "prototype_result=%ERRORLEVEL%"
echo.
echo Test exit code: %prototype_result%
pause
exit /b %prototype_result%
