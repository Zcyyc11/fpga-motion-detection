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
rem  Usage: build_vivado.bat [MODE_BG] [INPUT_SEL] [STAGE]
rem    MODE_BG  : 0 = frame diff, 1 = background model
rem    INPUT_SEL: 0 = 自测激励, 1 = 真实 HDMI 输入（默认 0，向后兼容）
rem    STAGE    : setup | synth | impl | bit | all（默认 all，分阶段见 tcl 头注释）
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

set INPUT_SEL=%~2
if "%INPUT_SEL%"=="" set INPUT_SEL=0

rem STAGE: setup / synth / impl / bit / all（默认 all）。分阶段构建见 tcl 头注释。
set STAGE=%~3
if "%STAGE%"=="" set STAGE=all

cd /d "%ROOT%"

rem --- 不再无条件清空工程目录 ------------------------------------------------
rem 旧版每次开头 rmdir /s /q build\vivado，分阶段构建下这会毁掉复用：
rem setup 阶段约 7 分钟的 IP 生成+OOC 综合成果全白做（2026-10-14 实测）。
rem 现在由 build_vivado.tcl 的 stage_setup 自己决定：工程存在则 open 复用，
rem 不存在才 create。要强制全新构建：先删掉 build\vivado 再跑 setup。
rem （ Vivado 自身 "file delete -force" 遇残留句柄会弹隐藏模态框死等，
rem   实测 10 分钟不动；所以要全新构建请用 OS 删除，别让 Vivado 删。)

rem Log is written by this script itself: PowerShell redirection would emit
rem UTF-16, which is awkward to read back with plain text tools.
set LOG=%LOGDIR%\vivado_build.log
echo ==== vivado build start %DATE% %TIME% (MODE_BG=%MODE_BG% INPUT_SEL=%INPUT_SEL% STAGE=%STAGE%) ==== > "%LOG%"
call vivado.bat -mode batch -nojournal -nolog -source "%SCRIPT_DIR%build_vivado.tcl" -tclargs %MODE_BG% %INPUT_SEL% %STAGE% >> "%LOG%" 2>&1

set RC=%errorlevel%
echo ==== vivado build exit code %RC% ==== >> "%LOG%"
exit /b %RC%
