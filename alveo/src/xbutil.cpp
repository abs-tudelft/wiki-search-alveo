
#include "xbutil.hpp"
#include <cstdio>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <array>
#include <glob.h>
#include <string.h>
#include <vector>
#include <sstream>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
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
 * StackOverflow copypasta for doing a filesystem glob.
 */
std::vector<std::string> glob(const std::string& pattern) {
    using namespace std;

    // glob struct resides on the stack
    glob_t glob_result;
    memset(&glob_result, 0, sizeof(glob_result));

    // do the glob operation
    int return_value = glob(pattern.c_str(), GLOB_TILDE, NULL, &glob_result);
    if(return_value != 0) {
        globfree(&glob_result);
        stringstream ss;
        ss << "glob() failed with return_value " << return_value << endl;
        throw std::runtime_error(ss.str());
    }

    // collect all the filenames into a std::list<std::string>
    vector<string> filenames;
    for(size_t i = 0; i < glob_result.gl_pathc; ++i) {
        filenames.push_back(string(glob_result.gl_pathv[i]));
    }

    // cleanup
    globfree(&glob_result);

    // done
    return filenames;
}

/**
 * Look for the sysfs directories containing the sensor data and clock
 * frequency readout files. If one or both are not found, nullptrs are
 * returned. This function caches its findings after its first call.
 */
static void get_paths(const std::string *&xmc_path_out, const std::string *&icap_path_out) {
    static bool first_run = true;
    static bool use_xbutil = true;
    static std::string xmc_path;
    static std::string icap_path;

    xmc_path_out = nullptr;
    icap_path_out = nullptr;

    if (!first_run) {
        if (!use_xbutil) {
            xmc_path_out = &xmc_path;
            icap_path_out = &icap_path;
        }
        return;
    }

    first_run = false;

    // Look for xmc node, which contains sensor readout files.
    auto paths = glob("/sys/bus/pci/devices/*/xmc.m.*");
    if (paths.empty()) {
        return;
    }
    xmc_path = paths.front();

    // Look for icap node, which contains the frequency readout file.
    paths = glob("/sys/bus/pci/devices/*/icap.m.*");
    if (paths.empty()) {
        return;
    }
    icap_path = paths.front();

    xmc_path_out = &xmc_path;
    icap_path_out = &icap_path;
}

/**
 * Reads the given (sysfs) file into a string.
 */
static std::string read_sysfs_string(const std::string &filename) {
    int fd = open(filename.c_str(), O_RDONLY);
    if (fd < 0) {
        return "";
    }

    std::string retval(64, 0);
    ssize_t size = read(fd, &retval[0], 64);
    close(fd);
    if (size < 0) {
        return "";
    }

    retval.resize(size);
    return retval;
}

/**
 * Reads the given number of values from the given sysfs file as floats and
 * pushes them into the given vector. If the read fails, zeros are pushed.
 */
static void read_sysfs_floats(const std::string &filename, int num_vals, std::vector<float> &data) {
    std::string str = read_sysfs_string(filename);
    for (int i = 0; i < num_vals; i++) {
        try {
            size_t pos = 0;
            data.push_back(std::stof(str, &pos));
            str = str.substr(pos);
        } catch (std::invalid_argument&) {
            data.push_back(0.0f);
        }
    }
}

/**
 * Runs `xbutil dump` and puts some information into the given structure.
 */
void xbutil_dump(XBUtilDumpInfo &info) {
    const std::string *xmc_path;
    const std::string *icap_path;
    get_paths(xmc_path, icap_path);

    std::vector<float> data;

    if (xmc_path == nullptr) {

        // Failed to find sysfs nodes to read the values we want, so fall back
        // to calling xbutil dump.
        auto board = nlohmann::json::parse(exec("xbutil dump"))["board"];
        data.push_back(std::stof(board["info"]["clock0"].get<std::string>()));
        data.push_back(std::stof(board["info"]["clock1"].get<std::string>()));
        data.push_back(std::stof(board["physical"]["thermal"]["fpga_temp"].get<std::string>()));
        data.push_back(std::stof(board["physical"]["electrical"]["12v_pex"]["voltage"].get<std::string>()));
        data.push_back(std::stof(board["physical"]["electrical"]["12v_pex"]["current"].get<std::string>()));
        data.push_back(std::stof(board["physical"]["electrical"]["12v_aux"]["voltage"].get<std::string>()));
        data.push_back(std::stof(board["physical"]["electrical"]["12v_aux"]["current"].get<std::string>()));
        data.push_back(std::stof(board["physical"]["electrical"]["vccint"]["voltage"].get<std::string>()));
        data.push_back(std::stof(board["physical"]["electrical"]["vccint"]["current"].get<std::string>()));

    } else {

        // Use sysfs nodes to query information.
        read_sysfs_floats(*icap_path + "/clock_freqs", 2, data);
        read_sysfs_floats(*xmc_path + "/xmc_fpga_temp", 1, data);
        read_sysfs_floats(*xmc_path + "/xmc_12v_pex_vol", 1, data);
        read_sysfs_floats(*xmc_path + "/xmc_12v_pex_curr", 1, data);
        read_sysfs_floats(*xmc_path + "/xmc_12v_aux_vol", 1, data);
        read_sysfs_floats(*xmc_path + "/xmc_12v_aux_curr", 1, data);
        read_sysfs_floats(*xmc_path + "/xmc_vccint_vol", 1, data);
        read_sysfs_floats(*xmc_path + "/xmc_vccint_curr", 1, data);

    }

    // Compute the requested values.
    info.clock0 = data[0];
    info.clock1 = data[1];
    info.fpga_temp = data[2];
    info.power_in = (data[3] * data[4] + data[5] * data[6]) * 0.000001f;
    info.power_vccint = data[7] * data[8] * 0.000001f;

}

