@echo off
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
