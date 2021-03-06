
#include "ffi.h"
#include "hardware.hpp"
#include "software.hpp"
#include "xbutil.hpp"
#include <string>
#include <memory>
#include <omp.h>
#include <stdlib.h>

typedef struct {

    // The most recent error message.
    std::string last_error;

    // Info about the current configuration, used for lazy reloading.
    std::string current_xclbin_prefix = "";
    std::string current_data_prefix = "";

    // Hardware implementation.
    std::shared_ptr<HardwareWordMatch> hw_impl;

    // Software implementation.
    std::shared_ptr<SoftwareWordMatch> sw_impl;

} state_type;

static state_type *state = NULL;

extern "C" {

/**
 * Returns the most recent error message.
 */
const char *word_match_last_error() {
    if (state == nullptr) {
        return "";
    }
    return state->last_error.c_str();
}

/**
 * Initializes the platform with the specified configuration. If the
 * configuration equals the current configuration, or does so partially,
 * only the necessary parts will be reloaded, unless `force_reload` is set, in
 * which case everything is reset. `progress` specifies a callback function
 * that will be called when there is new progress information. Its first
 * argument is set * to whatever is specified for `user`; `user` is not used by
 * this function otherwise. If this function returns `false` an error occured;
 * the error message can be retrieved using `word_match_last_error()`.
 */
int word_match_init(
    WordMatchPlatformConfig *config, int force_reload,
    void (*progress)(void *user, const char *status), void *user)
{
    if (state == nullptr) {
        state = new state_type;
        atexit(word_match_release);
    }

    try {

        // Check configuration.
        if (config == nullptr) {
            throw std::runtime_error("configuration must not be null");
        }

        // Figure out if we need to load the hardware implementation.
        if (config->xclbin_prefix != nullptr && config->xclbin_prefix[0]) {
            std::string xclbin_prefix = std::string(config->xclbin_prefix) + "." + config->emu_mode;
            if (force_reload || xclbin_prefix != state->current_xclbin_prefix) {

                // Reload hardware context.
                if (progress) progress(user, "Opening new Alveo OpenCL context...");
                state->hw_impl = std::make_shared<HardwareWordMatch>(
                    xclbin_prefix, config->kernel_name, config->num_subkernels, true);
                state->current_xclbin_prefix = xclbin_prefix;
                state->current_data_prefix = "";
                if (progress) progress(user, "Opening new Alveo OpenCL context... done");

            }
        } else if (force_reload) {

            // Forcibly release hardware context.
            if (progress) progress(user, "Releasing Alveo OpenCL context...");
            state->hw_impl = nullptr;
            state->current_xclbin_prefix = "";
            state->current_data_prefix = "";
            if (progress) progress(user, "Releasing Alveo OpenCL context... done");

        }

        // Figure out if we need to load the software implementation.
        if (config->keep_loaded && !state->sw_impl) {
            state->sw_impl = std::make_shared<SoftwareWordMatch>();
        } else if (!config->keep_loaded && state->sw_impl) {
            state->sw_impl = nullptr;
        }

        // Figure out if we need to reload the data.
        std::string data_prefix = std::string(config->data_prefix);
        if (data_prefix != state->current_data_prefix || force_reload) {
            std::vector<std::shared_ptr<WordMatch>> impls;
            if (state->hw_impl) impls.push_back(state->hw_impl);
            if (state->sw_impl) impls.push_back(state->sw_impl);
            WordMatchDatasetLoader(data_prefix, progress, user).load(impls);
            state->current_data_prefix = data_prefix;
        }

        return true;
    } catch (const std::exception& e) {
        state->last_error = e.what();
        return false;
    }
}

/**
 * Runs the (previously initialized) word matcher kernels with the given
 * configuration. `progress` specifies a callback function that will be called
 * when there is new progress information. Its first argument is set * to
 * whatever is specified for `user`; `user` is not used by this function
 * otherwise. If this function returns null an error occured; the error
 * message can be retrieved using `word_match_last_error()`. Otherwise, it
 * returns the results of the run, which remain valid only until the next FFI
 * call.
 */
const WordMatchResults *word_match_run(
    WordMatchRunConfig *config,
    void (*progress)(void *user, const char *status), void *user)
{
    if (state == nullptr) {
        return nullptr;
    }

    try {

        // Check configuration.
        if (config == nullptr) {
            throw std::runtime_error("configuration must not be null");
        }

        // Select which implementation to use.
        std::shared_ptr<WordMatch> impl;
        if (!config->mode) {
            if (!state->hw_impl) {
                throw std::runtime_error("hardware implementation is not loaded");
            }
            impl = state->hw_impl;
        } else {
            if (!state->sw_impl) {
                throw std::runtime_error("software implementation is not loaded");
            }
            if (config->mode > 0) {
                omp_set_dynamic(0);
                omp_set_num_threads(config->mode);
            } else {
                omp_set_dynamic(1);
                omp_set_num_threads(-config->mode);
            }
            impl = state->sw_impl;
        }

        // Construct the configuration.
        WordMatchConfig wmc(config->pattern, config->whole_words, config->min_matches);

        // Run the implementation.
        impl->execute(wmc, progress, user);

        // Return the results.
        return static_cast<const WordMatchResults*>(&impl->results);

    } catch (const std::exception& e) {
        state->last_error = e.what();
        return nullptr;
    }
}

/**
 * Queries health information from the Alveo board.
 */
WordMatchHealthInfo word_match_health() {
    WordMatchHealthInfo result;
    try {
        unsigned int index = 0;
        if (state->hw_impl) {
            index = state->hw_impl->get_device_index();
        }
        XBUtilDumpInfo info;
        xbutil_dump(info, index);
        result.fpga_temp = info.fpga_temp;
        result.power_in = info.power_in;
        result.power_vccint = info.power_vccint;
        return result;
    } catch (const std::exception& e) {
        if (state != nullptr) {
            state->last_error = e.what();
        }
        return result;
    }
}

/**
 * Free all resources.
 */
void word_match_release() {
    if (state == nullptr) {
        return;
    }
    try {
        state->hw_impl = nullptr;
        state->sw_impl = nullptr;
    } catch (const std::exception& e) {
        state->last_error = e.what();
    }
}

}
