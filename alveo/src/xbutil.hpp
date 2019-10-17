#pragma once

/**
 * Structure with some relevant information received from xbutil dump.
 */
typedef struct {

    // Clock frequencies in MHz.
    float clock0;
    float clock1;

    // FPGA temperature.
    float fpga_temp;

    // 12V input power.
    float power_in;

    // VccINT rail power.
    float power_vccint;

} XBUtilDumpInfo;

/**
 * Runs `xbutil dump` and puts some information into the given structure.
 */
void xbutil_dump(XBUtilDumpInfo &info);
