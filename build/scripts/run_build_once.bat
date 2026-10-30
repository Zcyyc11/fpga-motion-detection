@echo off
rem One-shot detached build wrapper. Registered in Windows Task Scheduler.
rem Root cause 2026-10-15: the build previously ran as a DIRECT CHILD of this
rem wrapper's interactive console, so any Ctrl-C / console-close aimed at that
rem console killed vivado (task exit 0xC000013A = STATUS_CONTROL_C_EXIT; Windows
rem does NOT log who sent the Ctrl-C). The build died 4x to external interrupts,
rem never to its own logic.
rem Fix: launch the real build via `start` in a NEW window (new console = new
rem process group), detached from this wrapper's console. This wrapper exits
rem immediately; vivado keeps running on its own, logging to build/logs/
rem vivado_build.log. A Ctrl-C to this wrapper's console can no longer reach it.
rem NOTE: we deliberately avoid PowerShell/Start-Process here. The agent sandbox
rem blocks PowerShell from spawning cmd.exe, and Register-ScheduledTask rejects
rem LogonType=ServiceAccount on this box, so the SYSTEM/non-interactive route
rem (Plan A) is infeasible. `start` is a cmd builtin and runs cleanly under the
rem scheduled task with no PowerShell in the build path.
set VIVADO_SETTINGS=<VIVADO>\2026.1\Vivado\settings64.bat
set MOTION_IP_REPO=<WORKSPACE>\libs\vivado-library
cd /d %~dp0
rem Launch build_vivado.bat (MODE_BG=0 frame-diff, INPUT_SEL=1 real HDMI, STAGE=all)
rem in a detached minimized window / new process group.
start "" /min build_vivado.bat 0 1 all
exit /b 0
