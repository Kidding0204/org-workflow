EMACS ?= emacs
export PACKAGE_USER_DIR ?= $(CURDIR)/.ci/elpa
RUN = $(EMACS) -Q --batch -l scripts/build-package.el --

.PHONY: bootstrap compile test lint checkdoc package smoke check clean
bootstrap:
	$(RUN) bootstrap
compile:
	$(RUN) compile
test:
	$(RUN) test
lint:
	$(RUN) lint
checkdoc:
	$(RUN) checkdoc
package:
	$(RUN) build
smoke: package
	$(RUN) smoke
check: compile test lint checkdoc smoke
clean:
	rm -rf dist
