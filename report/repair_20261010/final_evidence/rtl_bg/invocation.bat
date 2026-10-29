@echo off
setlocal
call "<DRIVE>/AMD2025.2\2025.2\Vivado\settings64.bat"
if errorlevel 1 exit /b 1
call xvlog.bat -sv -f files.f
if errorlevel 1 exit /b 2
call xelab.bat -debug typical -timescale 1ns/1ps tb_md_pipeline -generic_top "MODE_BG=1" -generic_top "FRAMES=12" -s line3_sim
if errorlevel 1 exit /b 3
call xsim.bat line3_sim -runall
exit /b %errorlevel%
