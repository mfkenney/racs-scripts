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
ADCFG := adc_config/$(shell hostname -s).yml

all: install

.PHONY: dirs
dirs:
	@echo "Creating data directories ..."
	$(INSTALL) -d $(DATADIRS)

install: dirs install-config install-bin install-adc-config

install-bin: $(SCRIPTS)
	@echo "Installing scripts ..."
	$(INSTALL) -d $(BINDIR)
	$(INSTALL) -m 755 $^ $(BINDIR)/

install-config: $(CFGFILES)
	@echo "Installing configuration files ..."
	$(INSTALL) -d $(CFGDIR)
	$(INSTALL) -m 644 $^ $(CFGDIR)/
	@echo "Installing Cron jobs ..."
	crontab $(CRONFILE)

install-adc-config: $(ADCFG)
	@echo "Installing A/D config file ..."
	$(INSTALL) -m 644 $(ADCFG) $(CFGDIR)/adc.yml
