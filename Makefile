.PHONY: build install clean

PREFIX ?= /usr/local/bin
BINARY = .build/release/media-desc

build:
	swift build -c release --disable-sandbox

install: build
	cp $(BINARY) $(PREFIX)/media-desc
	@echo "Installed to $(PREFIX)/media-desc"

clean:
	swift package clean
	rm -rf .build
