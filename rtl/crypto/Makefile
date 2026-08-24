# Makefile -- Xcelium (xrun), UVM-1.1d
# Run from rtl/crypto/ (files.f, tb/, and this Makefile all live there),
# since files.f uses paths like SHA/..., ALU/..., ed/..., otp.sv, top_most.sv, tb/....
#
# Usage:
#   make run
#   make cov_report
#   make clean

UVM_HOME  ?= $(CDS_INST_DIR)/tools/methodology/UVM/CDNS-1.1d/sv
COV_TEST  := tb_test_cov

XRUN_COMMON = -uvm -uvmhome $(UVM_HOME) -access +rwc -f files.f

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
