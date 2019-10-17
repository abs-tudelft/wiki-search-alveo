
#include "alveo.hpp"
#include "word_match.hpp"
#include "hardware.hpp"
#include "ffi.h"

static void reporter(void *user, const char *status) {
    printf("\033[A\033[K%s\n", status);
}

int main(int argc, char **argv) {

    // Parse command line.
    std::string data_prefix = (argc > 1) ? argv[1] : "/work/shared/fletcher-alveo/simplewiki";
    std::string bin_prefix  = (argc > 2) ? argv[2] : "xclbin/word_match";
    std::string kernel_name = (argc > 3) ? argv[3] : "krnl_word_match_rtl";

    // Check environment for emulation mode.
    const char *emu_mode = getenv("XCL_EMULATION_MODE");
    if (emu_mode == NULL) {
        emu_mode = "hw";
    }

    // Print what info about the mode we're running in.
    printf("Alveo Wikipedia search demo\n");
    printf(" - data source (\033[32marg 1\033[0m):\n   \033[32m%s\033[0m-<index>.rb\n", data_prefix.c_str());
    printf(" - xclbin prefix (\033[33marg 2\033[0m, \033[35menv\033[0m):\n   "
           "\033[33m%s\033[0m.\033[35m%s\033[0m.<device>.xclbin\n", bin_prefix.c_str(), emu_mode);
    printf(" - kernel name (\033[36marg 3\033[0m):\n   \033[36m%s\033[0m\n\n", kernel_name.c_str());

    // Initialize the platform.
    WordMatchPlatformConfig platcfg;
    platcfg.data_prefix = data_prefix.c_str();
    platcfg.xclbin_prefix = bin_prefix.c_str();
    platcfg.emu_mode = emu_mode;
    platcfg.kernel_name = kernel_name.c_str();
    platcfg.keep_loaded = true;
    printf("word_match_init...\n");
    if (!word_match_init(&platcfg, false, reporter, NULL)) {
        throw std::runtime_error(word_match_last_error());
    }

    try {

        while (true) {

            printf("> ");
            std::string pattern;
            while (true) {
                char c = fgetc(stdin);
                if (c == '\n') {
                    break;
                }
                pattern += c;
            }

            if (pattern.empty()) {
                break;
            }

            // Construct the run configuration.
            WordMatchRunConfig runcfg;
            if (pattern[0] == '~') {
                runcfg.pattern = pattern.c_str() + 1;
                runcfg.whole_words = true;
            } else {
                runcfg.pattern = pattern.c_str();
                runcfg.whole_words = false;
            }
            runcfg.min_matches = 1;

            // Run on hardware.
            runcfg.mode = 0;
            printf("word_match_run...\n");
            auto results = word_match_run(&runcfg, reporter, NULL);
            if (results == nullptr) {
                throw std::runtime_error(word_match_last_error());
            }

            // Print results.
            for (unsigned int i = 0; i < results->num_partial_results; i++) {
                auto p = results->partial_results[i];
                printf("kernel %u took %u cycles at %.0f MHz for %llu bytes = %.3f GB/s\n",
                    i, p->cycle_count, p->clock_frequency, p->data_size,
                    (p->data_size / (p->cycle_count / (p->clock_frequency * 1000000.0f))) / (1024.0f * 1024.0f * 1024.0f));
            }
            printf("\n%u pages matched & %u total matches within %.6fs on hardware\n",
                results->num_page_matches, results->num_word_matches,
                results->time_taken / 1000000.);
            if (results->max_word_matches) {
                printf("Best match is \"%s\", coming in at %u matches\n",
                    results->max_page_title, results->max_word_matches);
            }

            // Print FPGA health (mostly for testing the API).
            auto health = word_match_health();
            printf("fpga_temp=%.2f, power_in=%.2f, power_vccint=%.2f\n",
                health.fpga_temp, health.power_in, health.power_vccint);

            // Run on software.
            runcfg.mode = -1000;
            printf("word_match_run...\n");
            results = word_match_run(&runcfg, reporter, NULL);
            if (results == nullptr) {
                throw std::runtime_error(word_match_last_error());
            }

            // Print results.
            printf("\n%u pages matched & %u total matches within %.6fs on software\n",
                results->num_page_matches, results->num_word_matches,
                results->time_taken / 1000000.);
            if (results->max_word_matches) {
                printf("Best match is \"%s\", coming in at %u matches\n",
                    results->max_page_title, results->max_word_matches);
            }

        }

        word_match_release();
    } catch (std::exception &e) {
        printf("Error: %s\n", word_match_last_error());
        word_match_release();
        throw e;
    }
}
