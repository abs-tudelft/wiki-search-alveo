#pragma once

#include "ffi.h"
#include <string>
#include <vector>
#include <memory>
#include <arrow/api.h>
#include <unistd.h>

/**
 * Represents a search command for the word matcher.
 */
class WordMatchConfig {
public:
    std::string pattern;
    bool whole_words;
    uint16_t min_matches;

    WordMatchConfig(const std::string &pattern, bool whole_words=false, uint16_t min_matches=1)
        : pattern(pattern), whole_words(whole_words), min_matches(min_matches)
    {}
};

/**
 * Wrapper for `WordMatchPartialResults` that owns all contained data
 * STL-container style.
 */
class WordMatchPartialResultsContainer : public WordMatchPartialResults {
public:
    std::vector<unsigned int> cpp_page_match_counts;
    std::vector<unsigned int> cpp_page_match_title_offsets;
    std::string cpp_page_match_title_values;
    std::string cpp_max_page_title;

    /**
     * Updates the pointers in the C struct to point to the STL containers.
     * Must be called after any of the containers are resized/reallocated.
     */
    void synchronize();
};

/**
 * Wrapper for `WordMatchResults` that owns all contained data STL-container
 * style.
 */
class WordMatchResultsContainer : public WordMatchResults {
public:
    std::vector<WordMatchPartialResultsContainer> cpp_partial_results;

    /**
     * Updates the pointers in the C struct to point to the STL containers.
     * Must be called after any of the containers are resized/reallocated.
     */
    void synchronize();
};

/**
 * Base class for word matcher kernel implementations.
 */
class WordMatch {
public:

    /**
     * Container for the latest batch of results, updated by `execute()`.
     */
    WordMatchResultsContainer results;

    /**
     * Resets the dataset stored in device memory.
     */
    virtual void clear_chunks() = 0;

    /**
     * Adds the given chunk to the dataset stored in device memory.
     */
    virtual void add_chunk(const std::shared_ptr<arrow::RecordBatch> &batch) = 0;

    /**
     * Runs the kernel with the given configuration. The results are written to
     * `this->results`.
     */
    virtual void execute(const WordMatchConfig &config) = 0;

};

/**
 * Helper class to load datasets one chunk at a time.
 */
class WordMatchDatasetLoader {
private:
    std::string prefix;
    unsigned int num_batches;
    unsigned int cur_batch;
    bool quiet;
public:

    /**
     * Initializes a dataset loader with the given prefix, loading record
     * batches with filenames of the form `[prefix]-[index].rb`, with `[index]`
     * starting at 0.
     */
    WordMatchDatasetLoader(const std::string &prefix, bool quiet=false);

    /**
     * Loads and returns a pointer to the next record batch. Returns `nullptr`
     * after the last batch.
     */
    std::shared_ptr<arrow::RecordBatch> next();

    /**
     * Loads all (remaining) chunks into the given set of word matcher
     * implementations.
     */
    void load(std::vector<std::shared_ptr<WordMatch>> impls);

};
