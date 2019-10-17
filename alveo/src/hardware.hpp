#pragma once

#include "alveo.hpp"
#include "word_match.hpp"
#include "xcl2.hpp"
#include <inttypes.h>
#include <string>
#include <memory>
#include <arrow/api.h>

/**
 * Represents a search command for the hardware word matcher kernel.
 */
class HardwareWordMatchConfig {
public:
    uint32_t pattern_data[8];
    uint32_t search_config;
    HardwareWordMatchConfig(const WordMatchConfig &config);
};

/**
 * Class used internally by HardwareWordMatchKernel to keep track of the buffers for a given
 * record batch.
 */
class HardwareWordMatchDataChunk {
public:
    std::shared_ptr<arrow::Buffer> arrow_title_offsets;
    std::shared_ptr<arrow::Buffer> arrow_title_values;
    std::shared_ptr<AlveoBuffer> title_offset;
    std::shared_ptr<AlveoBuffer> title_values;
    std::shared_ptr<AlveoBuffer> text_offset;
    std::shared_ptr<AlveoBuffer> text_values;
    unsigned int num_rows;
};

/**
 * Manages a word matcher kernel, operating on a fixed record batch that is
 * only loaded once.
 */
class HardwareWordMatchKernel {
private:

    AlveoKernelInstance &context;
    unsigned int num_results;
    int bank;

    float clock0;
    float clock1;

    // Input buffers.
    std::vector<HardwareWordMatchDataChunk> chunks;
    unsigned int current_chunk;

    // Result buffers.
    std::shared_ptr<AlveoBuffer> result_title_offset;
    std::shared_ptr<AlveoBuffer> result_title_values;
    std::shared_ptr<AlveoBuffer> result_matches;
    std::shared_ptr<AlveoBuffer> result_stats;

    std::shared_ptr<AlveoBuffer> arrow_to_alveo(
        AlveoKernelInstance &context, int bank, const std::shared_ptr<arrow::Buffer> &buffer);

public:

    HardwareWordMatchKernel(const HardwareWordMatchKernel&) = delete;

    /**
     * Resets the dataset stored in device memory.
     */
    void clear_chunks();

    HardwareWordMatchKernel(
        AlveoKernelInstance &context,
        float clock0, float clock1, int num_results = 32);

    /**
     * Loads a recordbatch into the on-device OpenCL buffers for this instance.
     * Returns the chunk ID for the constructed chunk.
     */
    unsigned int add_chunk(const std::shared_ptr<arrow::RecordBatch> &batch);

    /**
     * Returns the number of loaded chunks.
     */
    unsigned int size() const;

    /**
     * Configures this instance with a search pattern and search configuration.
     */
    void configure(const HardwareWordMatchConfig &config);

private:

    /**
     * Runs this instance on a previously loaded chunk using the current
     * configuration.
     */
    cl_event enqueue_for_chunk_(unsigned int chunk);

public:

    /**
     * Runs this instance on a previously loaded chunk using the current
     * configuration. Returns the event object for the chunk to be waited
     * on.
     */
    std::shared_ptr<AlveoEvents> enqueue_for_chunk(unsigned int chunk);

    /**
     * Runs this instance on a previously loaded chunk using the current
     * configuration. Adds the event to an existing Alveo event object,
     */
    void enqueue_for_chunk(unsigned int chunk, AlveoEvents &events);

    /**
     * Loads the results for the most recent run into the given result buffer.
     */
    void get_results(WordMatchPartialResultsContainer &results);

    /**
     * Synchronously runs the kernel for the given chunk index, writing the
     * results (including execution time) to the given results buffer.
     */
    void execute_chunk(unsigned int chunk, WordMatchPartialResultsContainer &results);

};

/**
 * Alveo hardware implementation of the word matcher kernel.
 */
class HardwareWordMatch : public WordMatch {
private:
    AlveoContext context;
    std::vector<std::shared_ptr<HardwareWordMatchKernel>> kernels;
    unsigned int round_robin_state;
    unsigned int num_batches;

public:

    virtual ~HardwareWordMatch() = default;

    /**
     * Constructs the word matcher from an xclbin prefix excluding the
     * `.[device].xclbin` suffix (this is chosen automatically), and the name
     * of the kernel in the xclbin file.
     */
    HardwareWordMatch(const std::string &bin_prefix, const std::string &kernel_name, bool quiet=false);

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
