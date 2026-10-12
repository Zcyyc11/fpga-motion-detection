@echo off
setlocal
call "D:\AMD2025.2\2025.2\Vivado\settings64.bat"
if errorlevel 1 exit /b 10
call xvlog.bat -f files.f
if errorlevel 1 exit /b 11
call xelab.bat -debug typical -timescale 1ns/1ps tb_md_pipeline_full -s cosim
if errorlevel 1 exit /b 12
call xsim.bat cosim -runall
exit /b %errorlevel%
