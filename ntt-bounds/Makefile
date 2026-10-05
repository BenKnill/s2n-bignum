PYTHON ?= .venv/bin/python
HEARTH ?= hearth
RUN_ROOT ?= $(HOME)/lanes/ntt-bounds/runs
TIMEOUT ?= 7200

.PHONY: table generate replay test check-linear reduction analyze-reduction cold-replay
table:
	@$(PYTHON) bounds.py table
generate:
	@$(PYTHON) bounds.py generate $(if $(LINEAR),--linear,) $(if $(SPLIT_SAFETY),--split-safety,) $(FUNCTIONS)
replay:
	@$(PYTHON) bounds.py replay --hearth $(HEARTH) --run-root $(RUN_ROOT) --timeout $(TIMEOUT) $(if $(LINEAR),--linear,) $(if $(SPLIT_SAFETY),--split-safety,) $(FUNCTIONS)
test:
	@$(PYTHON) -m unittest -v test_bounds.py test_cold_replay.py
cold-replay:
	@$(PYTHON) cold_replay.py --checkout $(CHECKOUT) --hol $(HOLDIR) --run-root $(RUN_ROOT) --report COLD-REPLAY.md --timeout $(if $(COLD_TIMEOUT),$(COLD_TIMEOUT),10800)
check-linear:
	@$(HEARTH) prove check_linear.ml --profile light --timeout 120 --run-root $(RUN_ROOT)/linear-check
reduction:
	@$(PYTHON) bounds.py reduction --hearth $(HEARTH) --run-root $(RUN_ROOT)
analyze-reduction:
	@$(HEARTH) prove intt_reduction.ml --basis generated/mlkem_intt.ml --basis-cache-root $(RUN_ROOT) --profile s2n-arm-mlkem --timeout 7200 --run-root $(RUN_ROOT)/intt-reduction
	@$(MAKE) reduction
