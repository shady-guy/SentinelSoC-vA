# cov_report.tcl
# Opens the coverage session written by xrun (-coverage all) and dumps a
# text summary: line, toggle, FSM (code coverage) + covergroup
# (functional coverage) numbers.

set covdir "./xcelium.d/cov_work"
set testname "tb_test_cov"

cov load -database $covdir
cov report -summary -types line+toggle+fsm+block -out cov_summary_code.txt
cov report -summary -types assertion -out cov_summary_assert.txt
cov report -summary -types group    -out cov_summary_functional.txt

puts "Code coverage summary      : cov_summary_code.txt"
puts "Functional coverage summary: cov_summary_functional.txt"

exit
