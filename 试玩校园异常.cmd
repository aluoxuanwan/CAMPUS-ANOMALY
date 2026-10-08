@echo off
setlocal
if exist "%~dp0output\windows\CampusPrototype.exe" (
    start "" /d "%~dp0output\windows" "%~dp0output\windows\CampusPrototype.exe"
) else (
    start "" "%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0game"
)
