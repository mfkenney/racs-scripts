#
# Install RACS scripts and config files
#
SHELL = /bin/sh
INSTALL = install
CFGDIR := $(HOME)/config
BINDIR := $(HOME)/bin
DATADIRS := $(HOME)/archive $(HOME)/snapshots $(HOME)/INBOX $(HOME)/OUTBOX

SCRIPTS := $(wildcard *.sh)
CFGFILES := defaults settings
CRONFILE := jobs.cron

all: install

dirs:
	$(INSTALL) -d $(DATADIRS)

install: dirs install-config install-bin

install-bin: $(SCRIPTS)
	$(INSTALL) -d $(BINDIR)
	$(INSTALL) $^ $(BINDIR)/

install-config: $(CFGFILES)
	$(INSTALL) -d $(CFGDIR)
	$(INSTALL) -m 644 $^ $(CFGDIR)/
	crontab $(CRONFILE)
