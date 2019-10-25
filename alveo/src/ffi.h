#ifndef WORD_MATCH_FFI_H
#define WORD_MATCH_FFI_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Platform and dataset configuration structure.
 */
typedef struct {

    // Specifies the record batch files to load; filename format is
    // `[data_prefix].[index].rb`.
    const char *data_prefix;

    // Alveo binary information. The binary file loaded will be
    // `[xclbin_prefix].[emu_mode].[device].xclbin`, where `[device]` is
    // autodetected. `kernel_name` must specify the name of the kernel, and
    // num_subkernels must match the NUM_SUB generic in the hardware
    // description. If `data_prefix` is null or empty, the hardware will not
    // be loaded, and the other parameters are ignored.
    const char *xclbin_prefix;
    const char *emu_mode;
    const char *kernel_name;
    unsigned int num_subkernels;

    // Whether the data should remain loaded in memory to allow for software
    // runs.
    int keep_loaded;

} WordMatchPlatformConfig;

/**
 * Run configuration structure.
 */
typedef struct {

    // Specifies the string to look for.
    const char *pattern;

    // Specifies whether whole-word matching should be enabled.
    int whole_words;

    // Specifies how many matches must exist in a page for the page to be
    // considered to match.
    unsigned int min_matches;

    // Specifies whether the run should be done on hardware or in software, and
    // how many threads should be used in software mode. 0 indicates hardware;
    // 1 or more indicates software with the specified number of thread; -1 or
    // less indicates the same thing but with dynamic scheduling enabled (this
    // limits the thread count to the CPU thread count, so -1000 should give
    // the optimal number of threads).
    int mode;

} WordMatchRunConfig;

/**
 * Partial results of a single instance of the word match kernel, C-style for
 * IPC.
 */
typedef struct {

    // Total number of matched words accross all pages.
    unsigned int num_word_matches;

    // Total number of matched pages.
    unsigned int num_page_matches;

    // Info about the first N matched pages.
    unsigned int num_page_match_records;
    const unsigned int *page_match_counts;
    const unsigned int *page_match_title_offsets;
    const char *page_match_title_values;

    // Info about the page with the most matches.
    unsigned int max_word_matches;
    const char *max_page_title;

    // Number of (bus) cycles taken and the frequency of that clock, or 0 for
    // the software implementation.
    unsigned int cycle_count;
    float clock_frequency;

    // The approximate size of the input data to compute bandwidth (this is the
    // sum of the number of bytes in the article text values and offset
    // buffers).
    unsigned long long data_size;

    // Total amount of time taken (including overhead in starting the kernel
    // and transferring results back) in microseconds.
    unsigned int time_taken;

} WordMatchPartialResults;

/**
 * Complete result set for a single kernel invocation, C-style for IPC.
 */
typedef struct {

    // Total number of matched words accross all pages.
    unsigned int num_word_matches;

    // Total number of matched pages.
    unsigned int num_page_matches;

    // Info about the page with the most matches.
    unsigned int max_word_matches;
    const char *max_page_title;

    // Total amount of time taken in microseconds.
    unsigned int time_taken;

    // Partial results for each individual kernel invocation.
    unsigned int num_partial_results;
    WordMatchPartialResults **partial_results;

} WordMatchResults;

/**
 * Alveo board health information record.
 */
typedef struct {

    // FPGA temperature.
    float fpga_temp;

    // 12V input power.
    float power_in;

    // VccINT rail power.
    float power_vccint;

} WordMatchHealthInfo;

/**
 * Returns the most recent error message.
 */
const char *word_match_last_error();

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
    void (*progress)(void *user, const char *status),
    void *user);

/**
 * Runs the (previously initialized) word matcher kernels with the given
 * configuration. `progress` specifies a callback function that will be called
 * when there is new progress information. Its first argument is set * to
 * whatever is specified for `user`; `user` is not used by this function
 * otherwise. If this function returns `false` an error occured; the error
 * message can be retrieved using `word_match_last_error()`.
 */
const WordMatchResults *word_match_run(
    WordMatchRunConfig *config,
    void (*progress)(void *user, const char *status),
    void *user);

/**
 * Queries health information from the Alveo board.
 */
WordMatchHealthInfo word_match_health();

/**
 * Free all resources.
 */
void word_match_release();

#ifdef __cplusplus
}
#endif

#endif
