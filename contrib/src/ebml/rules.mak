# ebml

EBML_VERSION := 1.3.8
EBML_URL := http://dl.matroska.org/downloads/libebml/libebml-$(EBML_VERSION).tar.xz

ifeq ($(call need_pkg,"libebml >= 1.3.8"),)
PKGS_FOUND += ebml
endif

$(TARBALLS)/libebml-$(EBML_VERSION).tar.xz:
	$(call download_pkg,$(EBML_URL),ebml)

.sum-ebml: libebml-$(EBML_VERSION).tar.xz

ebml: libebml-$(EBML_VERSION).tar.xz .sum-ebml
	$(UNPACK)
	$(MOVE)

# libebml requires exceptions
EBML_CXXFLAGS := $(CXXFLAGS) $(PIC) -fexceptions -fvisibility=hidden

.ebml: ebml toolchain.cmake
	cd $< && CXXFLAGS="$(EBML_CXXFLAGS)" $(HOSTVARS_PIC) $(CMAKE) -DBUILD_SHARED_LIBS=OFF -DENABLE_WIN32_IO=OFF
	cd $< && $(MAKE) install
	touch $@
