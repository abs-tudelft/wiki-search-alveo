
#include "xbutil.hpp"
#include <cstdio>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <array>
#include "json.hpp"

/**
 * StackOverflow copypasta for running a process.
 */
static std::string exec(const char* cmd) {
    std::array<char, 128> buffer;
    std::string result;
    std::unique_ptr<FILE, decltype(&pclose)> pipe(popen(cmd, "r"), pclose);
    if (!pipe) {
        throw std::runtime_error("popen() failed!");
    }
    while (fgets(buffer.data(), buffer.size(), pipe.get()) != nullptr) {
        result += buffer.data();
    }
    return result;
}

/**
 * Runs `xbutil dump` and puts some information into the given structure.
 */
void xbutil_dump(XBUtilDumpInfo &info) {
    auto board = nlohmann::json::parse(exec("xbutil dump"))["board"];
    info.clock0 = std::stof(board["info"]["clock0"].get<std::string>());
    info.clock1 = std::stof(board["info"]["clock1"].get<std::string>());
    info.fpga_temp = std::stof(board["physical"]["thermal"]["fpga_temp"].get<std::string>());
    info.power_in  = (std::stof(board["physical"]["electrical"]["12v_pex"]["voltage"].get<std::string>()))
                   * (std::stof(board["physical"]["electrical"]["12v_pex"]["current"].get<std::string>()))
                   * 0.000001f;
    info.power_in += (std::stof(board["physical"]["electrical"]["12v_aux"]["voltage"].get<std::string>()))
                   * (std::stof(board["physical"]["electrical"]["12v_aux"]["current"].get<std::string>()))
                   * 0.000001f;
    info.power_vccint = (std::stof(board["physical"]["electrical"]["vccint"]["voltage"].get<std::string>()))
                      * (std::stof(board["physical"]["electrical"]["vccint"]["current"].get<std::string>()))
                      * 0.000001f;
}

