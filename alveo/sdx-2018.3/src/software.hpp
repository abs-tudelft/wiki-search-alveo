#pragma once

#include "word_match.hpp"
#include <inttypes.h>
#include <string>
#include <memory>
#include <arrow/api.h>

/**
 * Software implementation of the word matcher kernel.
 */
class SoftwareWordMatch : public WordMatch {
private:
    std::vector<std::shared_ptr<arrow::RecordBatch>> chunks;

public:

    virtual ~SoftwareWordMatch() = default;

    /**
     * Constructs the software word matcher.
     */
    SoftwareWordMatch();

    /**
     * Resets the dataset stored in device memory.
     */
    virtual void clear_chunks();

    /**
     * Adds the given chunk to the dataset stored in device memory.
     */
    virtual void add_chunk(const std::shared_ptr<arrow::RecordBatch> &batch);

    /**
     * Runs the kernel with the given configuration.
     */
    virtual void execute(const WordMatchConfig &config,
        void (*progress)(void *user, const char *status), void *progress_user);

};
