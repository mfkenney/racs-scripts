#
# Install RACS scripts and config files
#
SHELL = /bin/sh
INSTALL = install
CFGDIR := $(HOME)/config
BINDIR := $(HOME)/bin

SCRIPTS := $(wildcard *.sh)
CFGFILES := defaults settings
CRONFILE := jobs.cron

all: install

install: install-config install-bin

install-bin: $(SCRIPTS)
	$(INSTALL) $^ $(BINDIR)/

install-config: $(CFGFILES)
	$(INSTALL) -m 644 $^ $(CFGDIR)/
	crontab $(CRONFILE)
