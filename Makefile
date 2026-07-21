.PHONY: check install reproduce optimize demo

install:
	python -m pip install -e ".[dev]"

check:
	python -m ruff check sim models analysis tests demo
	python -m pytest tests/ -q
	python -m sim.reproduce --validate-only
	@echo OK - MS-C check passed

reproduce:
	python -m sim.reproduce

optimize:
	python -m sim.run_optimize --preset laptop

demo:
	python -m demo.app
