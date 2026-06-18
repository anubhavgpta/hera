# Hera UVM Regression Makefile
#
# Supported simulators:
#   TOOL=questa   -- Mentor Questa / ModelSim (default)
#   TOOL=xcelium  -- Cadence Xcelium
#   TOOL=vcs      -- Synopsys VCS (requires VCS + UVM library)
#
# Usage:
#   make smoke              # smoke test, seed=1
#   make stress             # stress test
#   make security           # security/quota/lock test
#   make soft_reset         # soft-reset recovery test
#   make regress            # all four tests in sequence
#   make sim TEST=hera_smoke_test SEED=42
#   make clean

TOOL ?= questa
SEED ?= 1
TEST ?= hera_smoke_test

RTL_DIR  := ../rtl
UVM_VERB ?= UVM_MEDIUM

RTL_SRCS := \
    $(RTL_DIR)/block_allocator.v  \
    $(RTL_DIR)/block_table.v      \
    $(RTL_DIR)/rw_engine.v        \
    $(RTL_DIR)/axi4_lite_if.v     \
    $(RTL_DIR)/prefetch_ctrl.v    \
    $(RTL_DIR)/eviction_engine.v  \
    $(RTL_DIR)/kv_cache_ctrl.v

IF_SRCS := \
    interfaces/hera_axi4_lite_if.sv \
    interfaces/hera_kv_wr_if.sv     \
    interfaces/hera_kv_rd_if.sv     \
    interfaces/hera_evict_if.sv

.PHONY: all compile sim smoke stress security soft_reset regress clean

all: smoke

# ===========================================================================
# Questa / ModelSim
# ===========================================================================
ifeq ($(TOOL),questa)

UVM_HOME ?= $(QUESTA_HOME)/verilog_src/uvm-1.2

compile:
	vlib work
	vmap work work
	vlog -sv -timescale 1ns/1ps \
	    +incdir+$(UVM_HOME)/src \
	    $(UVM_HOME)/src/uvm_pkg.sv \
	    $(RTL_SRCS) \
	    $(IF_SRCS) \
	    hera_uvm_pkg.sv \
	    tb_top.sv

sim: compile
	vsim -sv_seed $(SEED) \
	    +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(UVM_VERB) \
	    -do "coverage save -onexit cov_$(TEST)_$(SEED).ucdb; run -all; quit -f" \
	    tb_top

endif

# ===========================================================================
# Xcelium
# ===========================================================================
ifeq ($(TOOL),xcelium)

compile:
	xrun -elaborate -sv -uvm \
	    -timescale 1ns/1ps \
	    $(RTL_SRCS) \
	    $(IF_SRCS) \
	    hera_uvm_pkg.sv \
	    tb_top.sv \
	    -xmlibdirname xcelium.d

sim: compile
	xrun -R -sv_seed $(SEED) \
	    +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(UVM_VERB) \
	    -covoverwrite -coverage all

endif

# ===========================================================================
# VCS
# ===========================================================================
ifeq ($(TOOL),vcs)

UVM_HOME ?= $(VCS_HOME)/etc/uvm-1.2

compile:
	vcs -sverilog -timescale=1ns/1ps \
	    +incdir+$(UVM_HOME)/src \
	    $(UVM_HOME)/src/uvm_pkg.sv \
	    $(RTL_SRCS) \
	    $(IF_SRCS) \
	    hera_uvm_pkg.sv \
	    tb_top.sv \
	    -o simv

sim: compile
	./simv -sv_seed=$(SEED) \
	    +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(UVM_VERB)

endif

# ===========================================================================
# Named test targets
# ===========================================================================
smoke:
	$(MAKE) sim TEST=hera_smoke_test SEED=$(SEED)

stress:
	$(MAKE) sim TEST=hera_stress_test SEED=$(SEED)

security:
	$(MAKE) sim TEST=hera_security_test SEED=$(SEED)

soft_reset:
	$(MAKE) sim TEST=hera_soft_reset_test SEED=$(SEED)

# ===========================================================================
# Regression — run all tests, report PASS/FAIL per test
# ===========================================================================
TESTS := hera_smoke_test hera_stress_test hera_security_test hera_soft_reset_test

regress:
	@PASS=0; FAIL=0; \
	for t in $(TESTS); do \
	    echo ""; \
	    echo "=== $$t (seed=$(SEED)) ==="; \
	    $(MAKE) --no-print-directory sim TEST=$$t SEED=$(SEED) 2>&1 | tee $$t.log; \
	    if grep -q "TEST PASSED" $$t.log && ! grep -q "UVM_ERROR\s*[1-9]" $$t.log; then \
	        echo "RESULT: PASS"; PASS=$$((PASS+1)); \
	    else \
	        echo "RESULT: FAIL"; FAIL=$$((FAIL+1)); \
	    fi; \
	done; \
	echo ""; \
	echo "=== Regression Summary: $$PASS passed, $$FAIL failed ==="

# ===========================================================================
clean:
# ===========================================================================
clean:
	rm -rf work xcelium.d simv simv.daidir csrc *.log *.wlf *.shm \
	       *.ucdb *.vcd transcript *.db DVEfiles urgReport
