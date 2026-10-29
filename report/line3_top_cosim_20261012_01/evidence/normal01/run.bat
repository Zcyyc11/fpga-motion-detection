@echo off
setlocal
call "<DRIVE>/AMD2025.2\2025.2\Vivado\settings64.bat"
if errorlevel 1 exit /b 10
call xvlog.bat --relax -sv -f files.f
if errorlevel 1 exit /b 11
call xelab.bat -debug typical -timescale 1ns/1ps tb_line3_uart_cosim -generic_top "EVENTS=0" -s cosim
if errorlevel 1 exit /b 12
call xsim.bat cosim -runall
exit /b %errorlevel%
