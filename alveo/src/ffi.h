#ifndef WORD_MATCH_FFI_H
#define WORD_MATCH_FFI_H

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

    // Number of (bus) cycles taken, or 0 for the software implementation.
    unsigned int cycle_count;

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
    WordMatchPartialResults *partial_results;

} WordMatchResults;

#endif
