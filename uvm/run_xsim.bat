@echo off
setlocal

set VIVADO_BIN=D:\Vivado\2018.2\bin
set UVM_HOME=D:\Vivado\2018.2\data\system_verilog\uvm_1.2
set RTL=..\rtl
set TEST=%1
if "%TEST%"=="" set TEST=hera_smoke_test

echo ============================================================
echo  Hera UVM xsim run   TEST=%TEST%
echo ============================================================

:: Step 1 – compile RTL (Verilog-2001)
echo [1/4] Compiling RTL...
%VIVADO_BIN%\xvlog.bat -sv ^
    %RTL%\block_allocator.v ^
    %RTL%\block_table.v ^
    %RTL%\rw_engine.v ^
    %RTL%\axi4_lite_if.v ^
    %RTL%\prefetch_ctrl.v ^
    %RTL%\eviction_engine.v ^
    %RTL%\kv_cache_ctrl.v
if errorlevel 1 ( echo RTL compile FAILED & exit /b 1 )

:: Step 2 – compile UVM pkg + interfaces + TB
echo [2/4] Compiling UVM package and TB...
%VIVADO_BIN%\xvlog.bat -sv ^
    -i %UVM_HOME% ^
    interfaces\hera_axi4_lite_if.sv ^
    interfaces\hera_kv_wr_if.sv ^
    interfaces\hera_kv_rd_if.sv ^
    interfaces\hera_evict_if.sv ^
    hera_uvm_pkg.sv ^
    tb_top.sv
if errorlevel 1 ( echo TB compile FAILED & exit /b 1 )

:: Step 3 – elaborate
echo [3/4] Elaborating...
%VIVADO_BIN%\xelab.bat -sv -debug typical ^
    --timescale 1ns/1ps ^
    --snapshot tb_top_snap ^
    tb_top
if errorlevel 1 ( echo Elaboration FAILED & exit /b 1 )

:: Step 4 – simulate
echo [4/4] Simulating %TEST%...
%VIVADO_BIN%\xsim.bat tb_top_snap ^
    --runall ^
    --testplusarg "UVM_TESTNAME=%TEST%" ^
    --testplusarg "UVM_VERBOSITY=UVM_MEDIUM" ^
    --log %TEST%.log
if errorlevel 1 ( echo Simulation FAILED & exit /b 1 )

echo.
echo Log written to %TEST%.log
endlocal
