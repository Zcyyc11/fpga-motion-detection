@echo off
rem ASCII-only, CRLF wrapper: set env then run vivado batch build.
rem 2026-10-15: previous build_vivado.bat had Chinese comments that garble under
rem cmd codepages; and PS-tool background launches get killed by the 120s
rem default timeout. Task Scheduler session has neither problem.
set VIVADO_SETTINGS=D:\AMDDesignTools\2026.1\Vivado\settings64.bat
set MOTION_IP_REPO=D:\FPGA\libs\vivado-library
cd /d D:\FPGA\fpga-motion-detection
call "D:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" -mode batch -nojournal -nolog -source "D:\FPGA\fpga-motion-detection\build\scripts\build_vivado.tcl" -tclargs 0 1 all >> "D:\FPGA\fpga-motion-detection\build\logs\vivado_build.log" 2>&1
echo ==== wrapper exit code %errorlevel% ==== >> "D:\FPGA\fpga-motion-detection\build\logs\vivado_build.log"
exit /b %errorlevel%
