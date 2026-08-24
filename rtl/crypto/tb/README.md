# top_most UVM TB (Xcelium, UVM-1.1d)

## Structure
- `rfc8032_vectors_pkg.sv` — RFC 8032 §7.1 TEST 1 (0B msg) and TEST SHA(abc) (64B msg)
  KAT vectors, byte-verified. Both message lengths are multiples of 4 bytes.
  Also derives a corrupted-S variant for the negative test.
- `csr_if.sv` — OBI-style CSR bus + top-level status pins, driver/monitor clocking blocks.
- `otp_if.sv` — OTP BFM (combinational responder matching the documented
  OTP_REQ/OTP_LATCH protocol). Not `otp.sv` — that's an explicit foundry
  placeholder, per your note, so the TB doesn't couple to it.
- `probe_if.sv` — coverage-only hierarchical tap of the DUT's internal FSM state.
- `csr_seq_item.sv/driver/monitor/sequencer/agent` — single-master CSR agent.
- `csr_seq_lib.sv` — `rfc8032_kat_seq` (full R_IN x8 / S_IN x8 / MSG_LEN / CTRL.start
  / poll+DATA_IN flow per vector), `abort_seq` (mid-op abort and soft-reset),
  `top_virtual_seq` (runs: TEST1 pass, TEST1 corrupted-S fail, TEST SHA(abc) pass,
  abort, soft-reset).
- `test_oracle.sv` — hands expected pass/fail from the sequence to the scoreboard.
- `tb_scoreboard.sv` — pin-level check (`verify_done_o`/`signature_valid_o`).
  The CSR STATUS-register check (firmware view) is done inline in the sequence
  itself, per your "check both" requirement.
- `tb_coverage.sv` — functional coverage: CSR address hit, FSM state reached
  (all 18 states), `signature_valid_o` verified/unverified, CTRL.abort/softrst events.
- `tb_env.sv`, `tb_test.sv`, `tb_pkg.sv`, `tb_top.sv`, `files.f`, `Makefile`, `cov_report.tcl`.

## Open item — you need to supply these
`top_most` instantiates `sha512_msg_sched`, `sha512_round`, `sha512_pkg`,
`master_fsm`, `micro_sequencer`, `reg_file`, `alu_top`. These were referenced
by the RTL you pasted but never given to me, so I couldn't compile the DUT
end-to-end. Fill in their real paths in `files.f` (via `DUT_DIR`).

## Run
```
make DUT_DIR=/path/to/your/rtl run
make cov_report
```
`run` compiles with `-coverage all` (line/toggle/FSM code coverage +
covergroup functional coverage) and runs `tb_test`, which drives the full
`top_virtual_seq`. `cov_report` merges the DB via `imc` and writes
`cov_summary_code.txt` / `cov_summary_functional.txt`.

## Known assumptions worth double-checking against your firmware model
- CSR word packing: `wdata = {octet[4i+3],octet[4i+2],octet[4i+1],octet[4i]}`
  for R_IN/S_IN/DATA_IN/OTP words (confirmed by you).
- `start_verify_i` is pulsed once right after `CTRL.start` — it latches
  internally (`start_latch`) and is only consumed once the FSM reaches
  `ST_WAIT_START`, so timing isn't critical, but confirm this matches how
  your firmware actually sequences it (some designs pulse it later, after
  hash completion, as a discrete "go" from a second core).
- Abort/soft-reset is issued 5 clocks (50ns) after `CTRL.start`, while still
  inside `ST_FEED_R`. If you want it exercised at a different point (e.g.
  mid-SHA-block, mid-OTP-fetch), the delay in `abort_seq` is the one place to change.
