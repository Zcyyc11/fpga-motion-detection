@echo off
call "<DRIVE>/AMD2025.2/2025.2/Vivado/settings64.bat"
if errorlevel 1 exit /b 10
call xvlog.bat --relax -sv -f files.f
if errorlevel 1 exit /b 11
call xelab.bat tb_multi_bbox -s check
if errorlevel 1 exit /b 12
call xsim.bat check -tclbatch finish.tcl
exit /b %errorlevel%
