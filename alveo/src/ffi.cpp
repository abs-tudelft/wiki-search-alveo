
#include "ffi.h"
#include "hardware.hpp"
#include <string>
#include <memory>

// The most recent error message.
static std::string last_error;

// Info about the current configuration, used for lazy reloading.
static std::string current_xclbin_prefix = "";
static std::string current_data_prefix = "";

// Hardware implementation.
static std::shared_ptr<HardwareWordMatch> hw_impl;

extern "C" {

/**
 * Returns the most recent error message.
 */
const char *word_match_last_error() {
    return last_error.c_str();
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
bool word_match_init(
    WordMatchPlatformConfig &config, bool force_reload,
    void (*progress)(void *user, const char *status), void *user)
{
    try {

        // Figure out if we need to load the hardware.
        if (config.xclbin_prefix != nullptr && config.xclbin_prefix[0]) {
            std::string xclbin_prefix = std::string(config.xclbin_prefix) + "." + config.emu_mode;
            if (force_reload || xclbin_prefix != current_xclbin_prefix) {

                // Reload hardware context.
                if (progress) progress(user, "Opening new Alveo OpenCL context...");
                hw_impl = std::make_shared<HardwareWordMatch>(xclbin_prefix, config.kernel_name, true);
                current_xclbin_prefix = xclbin_prefix;
                current_data_prefix = "";
                if (progress) progress(user, "Opening new Alveo OpenCL context... done");

            }
        } else if (force_reload) {

            // Forcibly release hardware context.
            if (progress) progress(user, "Releasing Alveo OpenCL context...");
            hw_impl = nullptr;
            current_xclbin_prefix = "";
            current_data_prefix = "";
            if (progress) progress(user, "Releasing Alveo OpenCL context... done");

        }

        // Figure out if we need to reload the data.
        std::string data_prefix = std::string(config.data_prefix);
        if (data_prefix != current_data_prefix || force_reload) {
            std::vector<std::shared_ptr<WordMatch>> impls;
            if (hw_impl) impls.push_back(hw_impl);
            WordMatchDatasetLoader(data_prefix, progress, user).load(impls);
            current_data_prefix = data_prefix;
        }

        return true;
    } catch (const std::exception& e) {
        last_error = e.what();
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
    WordMatchRunConfig &config,
    void (*progress)(void *user, const char *status), void *user)
{
    try {

        // Select which implementation to use.
        std::shared_ptr<HardwareWordMatch> impl;
        if (!config.mode) {
            if (!hw_impl) {
                throw std::runtime_error("hardware implementation is not loaded");
            }
            impl = hw_impl;
        } else {
            throw std::runtime_error("software implementation is not loaded");
        }

        // Construct the configuration.
        WordMatchConfig wmc(config.pattern, config.whole_words, config.min_matches);

        // Run the implementation.
        impl->execute(wmc, progress, user);

        // Return the results.
        return static_cast<const WordMatchResults*>(&impl->results);

    } catch (const std::exception& e) {
        last_error = e.what();
        return nullptr;
    }
}

/**
 * Free all resources.
 */
void word_match_release() {
    hw_impl = nullptr;
}

}
