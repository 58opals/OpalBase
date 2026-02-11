SHELL := /bin/zsh

.PHONY: Setup Doctor Build Test TestLive

Setup:
	@./scripts/actions/setup.sh

Doctor:
	@./scripts/actions/doctor.sh

Build:
	@./scripts/actions/build.sh

Test:
	@./scripts/actions/test.sh

TestLive:
	@./scripts/actions/test-live.sh
