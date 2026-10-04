PYTHON ?= .venv/bin/python
HEARTH ?= hearth
RUN_ROOT ?= $(HOME)/lanes/ntt-bounds/runs

.PHONY: table generate replay test
table:
	@$(PYTHON) bounds.py table
generate:
	@$(PYTHON) bounds.py generate
replay:
	@$(PYTHON) bounds.py replay --hearth $(HEARTH) --run-root $(RUN_ROOT) $(FUNCTIONS)
test:
	@$(PYTHON) -m unittest -v test_bounds.py
