@echo off
setlocal
call "D:\AMD2025.2\2025.2\Vivado\settings64.bat"
if errorlevel 1 exit /b 1
call xvlog.bat -sv threshold.v morph_open.v morph3x3.v pattern_gen.v tb_contracts.v
if errorlevel 1 exit /b 2
call xelab.bat tb_contracts -s contracts
if errorlevel 1 exit /b 3
call xsim.bat contracts -runall
exit /b %errorlevel%
