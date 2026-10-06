# -*- coding: utf-8 -*-
"""Rewrite the two .bat launchers with CRLF + pure-ASCII content.

Why: cmd.exe (a) reads .bat in the OEM codepage so non-ASCII comments get
garbled into bogus commands, and (b) needs CRLF line endings -- with LF-only
endings it mis-parses `^` caret continuations, re-runs part of the script and
reports nonsense like "'n' is not recognized as an internal or external
command".  Both were live bugs in this repo.
"""
import os

ROOT = r'D:/FPGA/fpga-motion-detection'

BUILD_BAT = r'''@echo off
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
if "%VIVADO_SETTINGS%"=="" set VIVADO_SETTINGS=D:\AMDDesignTools\2026.1\Vivado\settings64.bat
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
'''

SIM_BAT = r'''@echo off
rem ============================================================================
rem  Run RTL simulation with Vivado xsim: xvlog -> xelab -> xsim.
rem
rem  NOTE 0: keep this file pure ASCII AND with CRLF line endings.
rem    LF-only endings make cmd.exe mis-parse the script; non-ASCII comments
rem    get garbled because cmd reads .bat in the OEM codepage (GBK here).
rem
rem  NOTE 1 (why the first line below cannot be removed):
rem    Without loading Vivado's environment, xelab still builds a snapshot
rem    fine, but xsim fails to start the engine with
rem      "Simulation engine failed to start ... status code -1073741515"
rem    0xC0000135 means DLL not found.  It looks like a design problem but is
rem    actually a missing environment.  Measured: adding the call fixes it.
rem
rem  Usage: run_sim.bat <top_module> <snapshot_name> <filelist>
rem ============================================================================
setlocal
call "D:\AMDDesignTools\2026.1\Vivado\settings64.bat" >nul 2>&1

set TOP=%~1
if "%TOP%"=="" set TOP=tb_md_pipeline
set SNAP=%~2
if "%SNAP%"=="" set SNAP=sim_%TOP%
set FL=%~3
if "%FL%"=="" set FL=files.f

cd /d "%~dp0"

echo === xvlog ===
call xvlog.bat -sv -f "%FL%"
if errorlevel 1 exit /b 2

echo === xelab ===
call xelab.bat -debug typical -timescale 1ns/1ps %TOP% -s %SNAP%
if errorlevel 1 exit /b 3

echo === xsim ===
call xsim.bat %SNAP% -runall
rem xsim.bat returns 0 whether or not the engine started, so the caller must
rem judge by the log content, not by the exit code.
exit /b 0
'''


def write_crlf(path, text):
    data = text.replace('\r\n', '\n').replace('\n', '\r\n').encode('ascii')
    with open(path, 'wb') as f:
        f.write(data)
    return data


out = []
for rel, text in (('build/scripts/build_vivado.bat', BUILD_BAT),
                  ('sim/run_sim.bat', SIM_BAT)):
    p = os.path.join(ROOT, rel)
    data = write_crlf(p, text)
    bare_lf = data.count(b'\n') - data.count(b'\r\n')
    out.append('%s  bytes=%d  CRLF=%d  bareLF=%d  pure_ascii=%s'
               % (rel, len(data), data.count(b'\r\n'), bare_lf,
                  all(c < 128 for c in data)))

print('\n'.join(out))
