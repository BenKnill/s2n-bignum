PYTHON ?= .venv/bin/python
HEARTH ?= hearth
RUN_ROOT ?= $(HOME)/lanes/ntt-bounds/runs

.PHONY: table generate replay test reduction analyze-reduction
table:
	@$(PYTHON) bounds.py table
generate:
	@$(PYTHON) bounds.py generate
replay:
	@$(PYTHON) bounds.py replay --hearth $(HEARTH) --run-root $(RUN_ROOT) $(FUNCTIONS)
test:
	@$(PYTHON) -m unittest -v test_bounds.py
reduction:
	@$(PYTHON) bounds.py reduction --hearth $(HEARTH) --run-root $(RUN_ROOT)
analyze-reduction:
	@$(HEARTH) prove intt_reduction.ml --basis generated/mlkem_intt.ml --basis-cache-root $(RUN_ROOT) --profile s2n-arm-mlkem --timeout 7200 --run-root $(RUN_ROOT)/intt-reduction
	@$(MAKE) reduction
