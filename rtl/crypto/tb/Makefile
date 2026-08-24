# Makefile -- Xcelium (xrun), UVM-1.1d
# Run from rtl/crypto/tb (files.f paths are relative to this directory).
#
# Usage:
#   make run          # compile + elaborate + simulate + coverage
#   make cov_report    # merge & dump coverage report (imc)
#   make clean

UVM_HOME  ?= $(CDS_INST_DIR)/tools/methodology/UVM/CDNS-1.1d/sv
COV_TEST  := tb_test_cov

XRUN_COMMON = -uvm -uvmhome $(UVM_HOME) -uvmnocdnsextra \
              -access +rwc \
              -f files.f

.PHONY: run cov_report clean

run:
	xrun $(XRUN_COMMON) \
		-coverage all -covoverwrite \
		-covtest $(COV_TEST) \
		+UVM_TESTNAME=tb_test \
		+UVM_VERBOSITY=UVM_LOW \
		+DUMP_WAVES

cov_report:
	imc -exec cov_report.tcl

clean:
	rm -rf xcelium.d xrun.log xrun.history waves.shm *.key