
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

//     // Construct the managers for the desired word matcher implementations.
//     std::vector<std::shared_ptr<WordMatch>> impls;
//
//     impls.push_back(std::make_shared<HardwareWordMatch>(bin_prefix + "." + emu_mode, kernel_name));
//
//     // Load the Wikipedia record batches and distribute them over the kernel
//     // instances.
//     WordMatchDatasetLoader(data_prefix).load(impls);
//
//     while (true) {
//
//         printf("> ");
//         std::string pattern;
//         while (true) {
//             char c = fgetc(stdin);
//             if (c == '\n') {
//                 break;
//             }
//             pattern += c;
//         }
//
//         if (pattern.empty()) {
//             return 0;
//         }
//
//         // Generate the implementation-agnostic configuration.
//         WordMatchConfig config(pattern);
//
//         impls[0]->execute(config);
//
//         printf("\n%u pages matched & %u total matches within %.6fs\n",
//             impls[0]->results.num_page_matches, impls[0]->results.num_word_matches,
//             impls[0]->results.time_taken / 1000000.);
//         if (impls[0]->results.max_word_matches) {
//             printf("Best match is \"%s\", coming in at %u matches\n",
//                 impls[0]->results.max_page_title, impls[0]->results.max_word_matches);
//         }
//
//     }

    // Initialize the platform.
    WordMatchPlatformConfig platcfg;
    platcfg.data_prefix = data_prefix.c_str();
    platcfg.xclbin_prefix = bin_prefix.c_str();
    platcfg.emu_mode = emu_mode;
    platcfg.kernel_name = kernel_name.c_str();
    platcfg.keep_loaded = false;
    printf("word_match_init...\n");
    if (!word_match_init(platcfg, false, reporter, NULL)) {
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

            // Do the run.
            WordMatchRunConfig runcfg;
            runcfg.pattern = pattern.c_str();
            runcfg.whole_words = false;
            runcfg.min_matches = 1;
            runcfg.mode = 0;
            printf("word_match_run...\n");
            auto results = word_match_run(runcfg, reporter, NULL);
            if (results == nullptr) {
                throw std::runtime_error(word_match_last_error());
            }

            // Print results.
            printf("\n%u pages matched & %u total matches within %.6fs\n",
                results->num_page_matches, results->num_word_matches,
                results->time_taken / 1000000.);
            if (results->max_word_matches) {
                printf("Best match is \"%s\", coming in at %u matches\n",
                    results->max_page_title, results->max_word_matches);
            }

        }

        word_match_release();
    } catch (std::exception &e) {
        word_match_release();
        throw e;
    }
}
