NVIM ?= nvim

.PHONY: test format check-format

test:
	$(NVIM) --clean --headless --cmd 'set rtp^=.' -c 'lua dofile("tests/emacs_spec.lua")({ exit = true })'

format:
	stylua lua tests

check-format:
	stylua --check lua tests
