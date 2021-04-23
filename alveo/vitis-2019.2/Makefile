.PHONY: help

help::
	$(ECHO) "Makefile Usage:"
	$(ECHO) "  make all TARGET=<sw_emu/hw_emu/hw> DEVICE=<FPGA platform> HOST_ARCH=<aarch32/aarch64/x86> SYSROOT=<sysroot_path>"
	$(ECHO) "      Command to generate the design for specified Target and Shell."
	$(ECHO) "      By default, HOST_ARCH=x86. HOST_ARCH and SYSROOT is required for SoC shells"
	$(ECHO) ""
	$(ECHO) "  make clean "
	$(ECHO) "      Command to remove the generated non-hardware files."
	$(ECHO) ""
	$(ECHO) "  make cleanall"
	$(ECHO) "      Command to remove all the generated files."
	$(ECHO) ""
	$(ECHO) "  make sd_card TARGET=<sw_emu/hw_emu/hw> DEVICE=<FPGA platform> HOST_ARCH=<aarch32/aarch64/x86> SYSROOT=<sysroot_path>"
	$(ECHO) "      Command to prepare sd_card files."
	$(ECHO) "      By default, HOST_ARCH=x86. HOST_ARCH and SYSROOT is required for SoC shells"
	$(ECHO) ""
	$(ECHO) "  make check TARGET=<sw_emu/hw_emu/hw> DEVICE=<FPGA platform> HOST_ARCH=<aarch32/aarch64/x86> SYSROOT=<sysroot_path>"
	$(ECHO) "      Command to run application in emulation."
	$(ECHO) "      By default, HOST_ARCH=x86. HOST_ARCH and SYSROOT is required for SoC shells"
	$(ECHO) ""
	$(ECHO) "  make build TARGET=<sw_emu/hw_emu/hw> DEVICE=<FPGA platform> HOST_ARCH=<aarch32/aarch64/x86> SYSROOT=<sysroot_path>"
	$(ECHO) "      Command to build xclbin application."
	$(ECHO) "      By default, HOST_ARCH=x86. HOST_ARCH and SYSROOT is required for SoC shells"
	$(ECHO) ""

TARGET := hw
HOST_ARCH := x86
SYSROOT :=
XCLBIN := ./xclbin
DEVICE = xilinx_u200_xdma_201920_1

include ./utils.mk

XSA := $(call device2xsa, $(DEVICE))
TEMP_DIR := ./_x.$(TARGET).$(XSA)
BUILD_DIR := ./build_dir.$(TARGET).$(XSA)

VPP := v++

# Definition of include file locations
OPENCL_INCLUDE:= $(XILINX_XRT)/include/
VIVADO_INCLUDE:= $(XILINX_VIVADO)/include/

opencl_CXXFLAGS=-I$(OPENCL_INCLUDE) -I$(VIVADO_INCLUDE)

OPENCL_LIB:=$(XILINX_XRT)/lib/
opencl_LDFLAGS=-L$(OPENCL_LIB) -lOpenCL -lpthread

xcl2_SRCS:=libs/xcl2/xcl2.cpp
xcl2_HDRS:=libs/xcl2/xcl2.hpp

xcl2_CXXFLAGS:=-Ilibs/xcl2 -fopenmp

#Include Libraries
CXXFLAGS += $(xcl2_CXXFLAGS)
LDFLAGS += $(xcl2_LDFLAGS)
HOST_SRCS += $(xcl2_SRCS)
include config.mk


#Include arrow
arrow_LDFLAGS=$(shell pkg-config --libs arrow)
arrow_CXXFLAGS=$(shell pkg-config --cflags arrow) -D_GLIBCXX_USE_CXX11_ABI=0

CXXFLAGS += $(arrow_CXXFLAGS)
LDFLAGS += $(arrow_LDFLAGS)

LDFLAGS += -lsnappy

CXXFLAGS += $(opencl_CXXFLAGS) -Wall -O0 -g -std=c++14
LDFLAGS += $(opencl_LDFLAGS)

CXXFLAGS += -O3

HOST_SRCS += src/alveo.cpp src/utils.cpp src/word_match.cpp src/hardware.cpp src/software.cpp src/xbutil.cpp src/ffi.cpp
HOST_HDRS += src/alveo.hpp src/utils.hpp src/word_match.hpp src/hardware.hpp src/software.hpp src/xbutil.hpp src/ffi.h
CXXFLAGS += -Isrc

# Host compiler global settings
CXXFLAGS += -fmessage-length=0
LDFLAGS += -lrt -lstdc++

# Kernel compiler global settings
CLFLAGS += -t $(TARGET) --platform $(DEVICE) --save-temps
ifneq ($(TARGET), hw)
	CLFLAGS += -g
endif


EXECUTABLE = host
CMD_ARGS = $(XCLBIN)/word_match.$(TARGET).$(XSA).xclbin
EMCONFIG_DIR = $(XCLBIN)/$(XSA)

BINARY_CONTAINERS += $(XCLBIN)/word_match.$(TARGET).$(XSA).xclbin
BINARY_CONTAINER_vadd_OBJS += $(XCLBIN)/word_match.$(TARGET).$(XSA).xo

CP = cp -rf

.PHONY: all clean cleanall docs emconfig
all: check-devices $(EXECUTABLE) $(BINARY_CONTAINERS) emconfig

.PHONY: exe
exe: $(EXECUTABLE)

.PHONY: build
build: $(BINARY_CONTAINERS)

# Building kernel
$(XCLBIN)/word_match.$(TARGET).$(XSA).xclbin: $(BINARY_CONTAINER_vadd_OBJS)
	mkdir -p $(XCLBIN)
ifeq ($(DEVICE),xilinx_u200_xdma_201920_1)
	$(VPP) $(CLFLAGS) -l $(LDCLFLAGS) -o $(XCLBIN)/word_match.$(TARGET).$(XSA).xclbin $(XCLBIN)/word_match.$(TARGET).$(XSA).xo \
		--nk krnl_word_match_rtl:15 \
		--sp krnl_word_match_rtl_1.m_axi:DDR[0] --slr krnl_word_match_rtl_1:SLR0 \
		--sp krnl_word_match_rtl_2.m_axi:DDR[0] --slr krnl_word_match_rtl_2:SLR0 \
		--sp krnl_word_match_rtl_3.m_axi:DDR[0] --slr krnl_word_match_rtl_3:SLR0 \
		--sp krnl_word_match_rtl_4.m_axi:DDR[0] --slr krnl_word_match_rtl_4:SLR0 \
		--sp krnl_word_match_rtl_5.m_axi:DDR[0] --slr krnl_word_match_rtl_5:SLR0 \
		--sp krnl_word_match_rtl_6.m_axi:DDR[1] \
		--sp krnl_word_match_rtl_7.m_axi:DDR[1] --slr krnl_word_match_rtl_7:SLR1 \
		--sp krnl_word_match_rtl_8.m_axi:DDR[1] --slr krnl_word_match_rtl_8:SLR1 \
		--sp krnl_word_match_rtl_9.m_axi:DDR[1] --slr krnl_word_match_rtl_9:SLR1 \
		--sp krnl_word_match_rtl_10.m_axi:DDR[1] \
		--sp krnl_word_match_rtl_11.m_axi:DDR[3] --slr krnl_word_match_rtl_11:SLR2 \
		--sp krnl_word_match_rtl_12.m_axi:DDR[3] --slr krnl_word_match_rtl_12:SLR2 \
		--sp krnl_word_match_rtl_13.m_axi:DDR[3] --slr krnl_word_match_rtl_13:SLR2 \
		--sp krnl_word_match_rtl_14.m_axi:DDR[3] --slr krnl_word_match_rtl_14:SLR2 \
		--sp krnl_word_match_rtl_15.m_axi:DDR[3] --slr krnl_word_match_rtl_15:SLR2 \
		--kernel_frequency '0:300|1:200'
else
ifeq ($(DEVICE),xilinx_u250_xdma_201830_2)
	$(VPP) $(CLFLAGS) -l $(LDCLFLAGS) -o $(XCLBIN)/word_match.$(TARGET).$(XSA).xclbin $(XCLBIN)/word_match.$(TARGET).$(XSA).xo \
		--nk krnl_word_match_rtl:15 \
		--sp krnl_word_match_rtl_1.m_axi:DDR[0] --slr krnl_word_match_rtl_1:SLR0 \
		--sp krnl_word_match_rtl_2.m_axi:DDR[0] --slr krnl_word_match_rtl_2:SLR0 \
		--sp krnl_word_match_rtl_3.m_axi:DDR[0] --slr krnl_word_match_rtl_3:SLR0 \
		--sp krnl_word_match_rtl_4.m_axi:DDR[0] --slr krnl_word_match_rtl_4:SLR0 \
		--sp krnl_word_match_rtl_5.m_axi:DDR[0] --slr krnl_word_match_rtl_5:SLR0 \
		--sp krnl_word_match_rtl_6.m_axi:DDR[1] --slr krnl_word_match_rtl_6:SLR1 \
		--sp krnl_word_match_rtl_7.m_axi:DDR[1] --slr krnl_word_match_rtl_7:SLR1 \
		--sp krnl_word_match_rtl_8.m_axi:DDR[1] --slr krnl_word_match_rtl_8:SLR1 \
		--sp krnl_word_match_rtl_9.m_axi:DDR[1] --slr krnl_word_match_rtl_9:SLR1 \
		--sp krnl_word_match_rtl_10.m_axi:DDR[1] --slr krnl_word_match_rtl_10:SLR1\
		--sp krnl_word_match_rtl_11.m_axi:DDR[2] --slr krnl_word_match_rtl_11:SLR2 \
		--sp krnl_word_match_rtl_12.m_axi:DDR[2] --slr krnl_word_match_rtl_12:SLR2 \
		--sp krnl_word_match_rtl_13.m_axi:DDR[2] --slr krnl_word_match_rtl_13:SLR2 \
		--sp krnl_word_match_rtl_14.m_axi:DDR[2] --slr krnl_word_match_rtl_14:SLR2 \
		--sp krnl_word_match_rtl_15.m_axi:DDR[2] --slr krnl_word_match_rtl_15:SLR2 \
		--kernel_frequency '0:300|1:200'
endif
endif
# 	$(VPP) $(CLFLAGS) --temp_dir $(BUILD_DIR) -l $(LDCLFLAGS) -o'$@' $(+)


# Building Host
$(EXECUTABLE): check-xrt $(HOST_SRCS) $(HOST_HDRS)
	$(CXX) $(CXXFLAGS) $(HOST_SRCS) -fPIC -shared -o libwordmatch.so $(LDFLAGS)
	$(CXX) $(CXXFLAGS) src/host.cpp -L . -lwordmatch -Wl,-rpath,. -o '$@' $(LDFLAGS)
	rm -f ../libwordmatch.so
	ln -sf vitis-2019.2/libwordmatch.so ../libwordmatch.so
	ln -sf vitis-2019.2/src/ffi.h ../ffi.h

emconfig:$(EMCONFIG_DIR)/emconfig.json
$(EMCONFIG_DIR)/emconfig.json:
	emconfigutil --platform $(DEVICE) --od $(EMCONFIG_DIR)

check: all
ifeq ($(TARGET),$(filter $(TARGET),sw_emu hw_emu))
ifeq ($(HOST_ARCH), x86)
	$(CP) $(EMCONFIG_DIR)/emconfig.json .
	XCL_EMULATION_MODE=$(TARGET) ./$(EXECUTABLE) $(BUILD_DIR)/vadd.xclbi
endif
else
ifeq ($(HOST_ARCH), x86)
	./$(EXECUTABLE) $(BUILD_DIR)/vadd.xclbin
endif
endif
ifneq ($(TARGET),$(findstring $(TARGET), hw hw_emu))
$(warning WARNING:Application supports only hw hw_emu TARGET. Please use the target for running the application)
endif

ifeq ($(HOST_ARCH), x86)
	perf_analyze profile -i profile_summary.csv -f html
endif

# Cleaning stuff
clean:
	-$(RMDIR) $(EXECUTABLE) $(XCLBIN)/{*sw_emu*,*hw_emu*}
	-$(RMDIR) profile_* TempConfig system_estimate.xtxt *.rpt *.csv
	-$(RMDIR) src/*.ll *v++* .Xil emconfig.json dltmp* xmltmp* *.log *.jou *.wcfg *.wdb

cleanall: clean
	-$(RMDIR) build_dir* sd_card*
	-$(RMDIR) _x.* *xclbin.run_summary qemu-memory-_* emulation/ _vimage/ pl* start_simulation.sh *.xclbin
	-$(RMDIR) ./tmp_kernel_pack* ./packaged_kernel*
