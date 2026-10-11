@echo off
rem ============================================================================
rem  Run the full Vivado build from source to bitstream.
rem
rem  NOTE 1: keep this file pure ASCII AND with CRLF line endings.
rem          cmd.exe reads .bat in the OEM codepage (GBK here), so non-ASCII
rem          comments get garbled; and LF-only endings make cmd mis-parse
rem          continuation lines (it then re-runs parts of the script and
rem          reports bogus errors like "'n' is not recognized").
rem          For the same reason every command below sits on ONE physical line:
rem          no ^ caret continuation.
rem  NOTE 2: settings64.bat must be called first, otherwise vivado.bat cannot
rem          find its own libraries.
rem
rem  Usage: build_vivado.bat [MODE_BG]   (0 = frame diff, 1 = background model)
rem  Log  : build/logs/vivado_build.log
rem ============================================================================
setlocal
rem Vivado location is configurable: set VIVADO_SETTINGS before calling.
rem No machine-specific default any more -- error out with guidance if unset.
if "%VIVADO_SETTINGS%"=="" (
    echo ERROR: VIVADO_SETTINGS is not set. Point it at the full path to settings64.bat on your machine.
    echo   e.g.  set VIVADO_SETTINGS=^<your Vivado install dir^>\Vivado\settings64.bat
    echo   or set env XILINX_VIVADO to the Vivado install directory.
    exit /b 9
)
call "%VIVADO_SETTINGS%" >nul 2>&1
if errorlevel 1 (
    echo ERROR: cannot load Vivado environment from "%VIVADO_SETTINGS%"
    exit /b 9
)

set SCRIPT_DIR=%~dp0
set ROOT=%SCRIPT_DIR%..\..
set LOGDIR=%ROOT%\build\logs
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

set MODE_BG=%~1
if "%MODE_BG%"=="" set MODE_BG=0

cd /d "%ROOT%"

rem --- Clean the project directory with the OS, NEVER with Vivado ------------
rem Vivado's own "file delete -force" hangs when a stale file handle is present:
rem it pops a HIDDEN modal dialog and waits forever.  Measured: 10+ minutes
rem stuck, process idle at 15 MB with window title "OLEChannelWnd".
rem rmdir /s /q is native, dialog-free, and removed the same tree in ~2 s.
set PROJ=%ROOT%\build\vivado
if exist "%PROJ%" rmdir /s /q "%PROJ%"
if exist "%PROJ%" echo WARNING: could not fully remove "%PROJ%"

rem Log is written by this script itself: PowerShell redirection would emit
rem UTF-16, which is awkward to read back with plain text tools.
set LOG=%LOGDIR%\vivado_build.log
echo ==== vivado build start %DATE% %TIME% (MODE_BG=%MODE_BG%) ==== > "%LOG%"
call vivado.bat -mode batch -nojournal -nolog -source "%SCRIPT_DIR%build_vivado.tcl" -tclargs %MODE_BG% >> "%LOG%" 2>&1

set RC=%errorlevel%
echo ==== vivado build exit code %RC% ==== >> "%LOG%"
exit /b %RC%
