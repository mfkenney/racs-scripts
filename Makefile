#
# Install RACS scripts and config files
#
SHELL = /bin/sh
CFGDIR := $(HOME)/config
BINDIR := $(HOME)/bin

SCRIPTS := $(wildcard *.sh)
CFGFILES := defaults settings

all: install

install: install-config install-bin

install-bin: $SCRIPTS
	$(INSTALL) $^ $BINDIR/

install-config:
	$(INSTALL) -m 644 $^ $CFGDIR/
