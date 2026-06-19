@echo off
setlocal

:: ============================================================
::  Hera KV Cache Controller -- xsim 2018.2 simulation
::
::  Zero-UVM class-based SystemVerilog testbench.
::  Runs 4 test scenarios (Smoke, Stress, Security, Soft Reset).
::  Expected result: 41 / 41 checks PASS.
::
::  Usage (from this directory):
::    sim\run_xsim.bat
::
::  Requires Vivado 2018.2. Adjust VIVADO_BIN if installed elsewhere.
:: ============================================================

set VIVADO_BIN=D:\Vivado\2018.2\bin
set RTL=..\rtl
set SNAP=hera_snap
set LOG=hera_sim.log

echo ============================================================
echo  Hera -- xsim 2018.2
echo ============================================================

:: Step 1 -- compile RTL
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

:: Step 2 -- compile interfaces + testbench
echo [2/4] Compiling interfaces and testbench...
%VIVADO_BIN%\xvlog.bat -sv ^
    interfaces\hera_axi4_lite_if.sv ^
    interfaces\hera_kv_wr_if.sv ^
    interfaces\hera_kv_rd_if.sv ^
    interfaces\hera_evict_if.sv ^
    tb_sv_top.sv
if errorlevel 1 ( echo TB compile FAILED & exit /b 1 )

:: Step 3 -- elaborate
echo [3/4] Elaborating...
%VIVADO_BIN%\xelab.bat -sv ^
    --timescale 1ns/1ps ^
    --snapshot %SNAP% ^
    tb_sv_top
if errorlevel 1 ( echo Elaboration FAILED & exit /b 1 )

:: Step 4 -- simulate
echo [4/4] Simulating...
%VIVADO_BIN%\xsim.bat %SNAP% ^
    --runall ^
    --log %LOG%
if errorlevel 1 ( echo Simulation FAILED & exit /b 1 )

echo.
echo Log: %LOG%
endlocal
