VHDL_FILES = $(shell python3 -m vhdeps dump krnl_word_match_rtl \
               -i src \
               -i ../hardware/vhdl \
               -i ../../fletcher/hardware \
               -x ../../vhsnunzip/vhdl \
               -msyn -v93 | cut -d ' ' -f 4-)

VIVADO := $(XILINX_VIVADO)/bin/vivado
$(XCLBIN)/word_match.$(TARGET).$(DSA).xo: src/kernel.xml scripts/package_kernel.tcl scripts/gen_xo.tcl $(VHDL_FILES)
	mkdir -p $(XCLBIN)
	rm -rf all-sources
	mkdir -p all-sources
	cp -t all-sources $(VHDL_FILES)
	$(VIVADO) -mode batch -source scripts/gen_xo.tcl -tclargs $(XCLBIN)/word_match.$(TARGET).$(DSA).xo word_match $(TARGET) $(DSA)
