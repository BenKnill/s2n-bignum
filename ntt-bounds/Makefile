PYTHON ?= .venv/bin/python
HEARTH ?= hearth
RUN_ROOT ?= $(HOME)/lanes/ntt-bounds/runs

.PHONY: table generate replay test check-linear reduction analyze-reduction
table:
	@$(PYTHON) bounds.py table
generate:
	@$(PYTHON) bounds.py generate $(if $(LINEAR),--linear,)
replay:
	@$(PYTHON) bounds.py replay --hearth $(HEARTH) --run-root $(RUN_ROOT) $(if $(LINEAR),--linear,) $(FUNCTIONS)
test:
	@$(PYTHON) -m unittest -v test_bounds.py
check-linear:
	@$(HEARTH) prove check_linear.ml --profile light --timeout 120 --run-root $(RUN_ROOT)/linear-check
reduction:
	@$(PYTHON) bounds.py reduction --hearth $(HEARTH) --run-root $(RUN_ROOT)
analyze-reduction:
	@$(HEARTH) prove intt_reduction.ml --basis generated/mlkem_intt.ml --basis-cache-root $(RUN_ROOT) --profile s2n-arm-mlkem --timeout 7200 --run-root $(RUN_ROOT)/intt-reduction
	@$(MAKE) reduction
