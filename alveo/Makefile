.PHONY: help

help::
	$(ECHO) "Makefile Usage:"
	$(ECHO) "  make all TARGET=<sw_emu/hw_emu/hw> DEVICE=<FPGA platform>"
	$(ECHO) "      Command to generate the design for specified Target and Device."
	$(ECHO) ""
	$(ECHO) "  make clean "
	$(ECHO) "      Command to remove the generated non-hardware files."
	$(ECHO) ""
	$(ECHO) "  make cleanall"
	$(ECHO) "      Command to remove all the generated files."
	$(ECHO) ""
	$(ECHO) "  make check TARGET=<sw_emu/hw_emu/hw> DEVICE=<FPGA platform>"
	$(ECHO) "      Command to run application in emulation."
	$(ECHO) ""
	$(ECHO) "  make build TARGET=<sw_emu/hw_emu/hw> DEVICE=<FPGA platform>"
	$(ECHO) "      Command to build xclbin application."
	$(ECHO) ""

TARGETS := hw
TARGET := $(TARGETS)
DEVICE := $(DEVICES)
XCLBIN := ./xclbin

include ./utils.mk

DSA := $(call device2dsa, $(DEVICE))
BUILD_DIR := ./_x.$(TARGET).$(DSA)

BUILD_DIR_word_match = $(BUILD_DIR)/word_match

CXX := $(XILINX_SDX)/bin/xcpp
XOCC := $(XILINX_SDX)/bin/xocc

# Definition of include file locations
OPENCL_INCLUDE:= $(XILINX_XRT)/include/
VIVADO_INCLUDE:= $(XILINX_VIVADO)/include/

opencl_CXXFLAGS=-I$(OPENCL_INCLUDE) -I$(VIVADO_INCLUDE)

OPENCL_LIB:=$(XILINX_XRT)/lib/
opencl_LDFLAGS=-L$(OPENCL_LIB) -lOpenCL -lpthread

xcl2_SRCS:=libs/xcl2/xcl2.cpp
xcl2_HDRS:=libs/xcl2/xcl2.hpp

xcl2_CXXFLAGS:=-Ilibs/xcl2

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

CXXFLAGS += $(opencl_CXXFLAGS) -Wall -O0 -g -std=c++14
LDFLAGS += $(opencl_LDFLAGS)

HOST_SRCS += src/host.cpp

# Host compiler global settings
CXXFLAGS += -fmessage-length=0
LDFLAGS += -lrt -lstdc++

# Kernel compiler global settings
CLFLAGS += -t $(TARGET) --platform $(DEVICE) --save-temps


EXECUTABLE = host
CMD_ARGS = $(XCLBIN)/word_match.$(TARGET).$(DSA).xclbin

EMCONFIG_DIR = $(XCLBIN)/$(DSA)

BINARY_CONTAINERS += $(XCLBIN)/word_match.$(TARGET).$(DSA).xclbin
BINARY_CONTAINER_word_match_OBJS += $(XCLBIN)/word_match.$(TARGET).$(DSA).xo

CP = cp -rf

.PHONY: all clean cleanall docs emconfig
all: check-devices $(EXECUTABLE) $(BINARY_CONTAINERS) emconfig

.PHONY: exe
exe: $(EXECUTABLE)

.PHONY: build
build: $(BINARY_CONTAINERS)

# Building kernel
$(XCLBIN)/word_match.$(TARGET).$(DSA).xclbin: $(BINARY_CONTAINER_word_match_OBJS)
	mkdir -p $(XCLBIN)
	# TODO(mb): hw_emu target -g flag for traces
	$(XOCC) $(CLFLAGS) $(LDCLFLAGS) -lo $(XCLBIN)/word_match.$(TARGET).$(DSA).xclbin $(XCLBIN)/word_match.$(TARGET).$(DSA).xo --nk krnl_word_match_rtl:12 --kernel_frequency 250

# Building Host
$(EXECUTABLE): check-xrt $(HOST_SRCS) $(HOST_HDRS)
	$(CXX) $(CXXFLAGS) $(HOST_SRCS) $(HOST_HDRS) -o '$@' $(LDFLAGS)

emconfig:$(EMCONFIG_DIR)/emconfig.json
$(EMCONFIG_DIR)/emconfig.json:
	emconfigutil --platform $(DEVICE) --od $(EMCONFIG_DIR)

check: all
ifeq ($(TARGET),$(filter $(TARGET),sw_emu hw_emu))
	$(CP) $(EMCONFIG_DIR)/emconfig.json .
	XCL_EMULATION_MODE=$(TARGET) ./$(EXECUTABLE) $(XCLBIN)/word_match.$(TARGET).$(DSA).xclbin
else
	 ./$(EXECUTABLE) $(XCLBIN)/word_match.$(TARGET).$(DSA).xclbin
endif
ifneq ($(TARGET),$(findstring $(TARGET), hw hw_emu))
$(warning WARNING:Application supports only hw hw_emu TARGET. Please use the target for running the application)
endif

	sdx_analyze profile -i profile_summary.csv -f html

# Cleaning stuff
clean:
	-$(RMDIR) $(EXECUTABLE) $(XCLBIN)/{*sw_emu*,*hw_emu*}
	-$(RMDIR) profile_* TempConfig system_estimate.xtxt *.rpt *.csv
	-$(RMDIR) src/*.ll _xocc_* .Xil emconfig.json dltmp* xmltmp* *.log *.jou *.wcfg *.wdb

cleanall: clean
	-$(RMDIR) $(XCLBIN)
	-$(RMDIR) _x.*
	-$(RMDIR) ./tmp_kernel_pack* ./packaged_kernel*
