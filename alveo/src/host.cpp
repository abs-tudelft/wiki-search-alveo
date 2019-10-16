
#include "alveo.hpp"
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <inttypes.h>
#include <string>
#include <memory>
#include <arrow/api.h>
#include <arrow/io/api.h>
#include <arrow/ipc/api.h>
#include <omp.h>

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
    void synchronize() {
        max_page_title = cpp_max_page_title.c_str();
        num_page_match_records = cpp_page_match_counts.size();
        page_match_counts = cpp_page_match_counts.data();
        page_match_title_offsets = cpp_page_match_title_offsets.data();
        page_match_title_values = cpp_page_match_title_values.c_str();
    }
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
    void synchronize() {
        num_partial_results = cpp_partial_results.size();
        partial_results = cpp_partial_results.data();
    }
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

#if 0
// /**
//  * Represents an set of input record batches for the word matcher, stored in
//  * host memory.
//  */
// class WordMatchDataset {
// private:
//     std::vector<std::shared_ptr<arrow::RecordBatch>> chunks;
//
// public:
//
//     /**
//      * Adds the given chunk to the dataset.
//      */
//     void add_chunk(std::shared_ptr<arrow::RecordBatch> chunk) {
//         chunks.push_back(chunk);
//     }
//
//     /**
//      * Clears all the chunks out of this dataset.
//      */
//     void clear() {
//         chunks.clear();
//     }
//
//     /**
//      * Returns the number of loaded chunks.
//      */
//     unsigned int size() const {
//         return chunks.size();
//     }
//
//     /**
//      * Returns the record batch for the given chunk index for the hardware
//      * implementation.
//      */
//     std::shared_ptr<arrow::RecordBatch> get_chunk(int index = -1) {
//         if (index < 0) {
//             return chunks.back();
//         } else {
//             return chunks[index];
//         }
//     }
//
//     /**
//      * Returns the entire dataset as an arrow table for the software
//      * implementation.
//      */
//     std::shared_ptr<arrow::Table> as_table() {
//         std::shared_ptr<arrow::Table> table;
//         arrow::Status status = arrow::Table::FromRecordBatches(chunks, &table);
//         if (!status.ok()) {
//             throw std::runtime_error("Table::FromRecordBatches failed: " + status.ToString());
//         }
//         return table;
//     }
//
// };
#endif

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
    WordMatchDatasetLoader(const std::string &prefix, bool quiet=false)
        : prefix(prefix), num_batches(0), cur_batch(0), quiet(quiet)
    {

        // Figure out how many batches there are.
        for (;; num_batches++) {
            std::string batch_filename = prefix + "-" + std::to_string(num_batches) + ".rb";
            if (access(batch_filename.c_str(), F_OK) == -1) {
                break;
            }
        }
        if (!num_batches) {
            throw std::runtime_error("no record batches found for prefix " + prefix);
        }

        if (!quiet) printf("\n");
    }

    /**
     * Loads and returns a pointer to the next record batch. Returns `nullptr`
     * after the last batch.
     */
    std::shared_ptr<arrow::RecordBatch> next() {

        // Handle end of iteration.
        if (cur_batch >= num_batches) {
            if (!quiet) printf("\033[A\033[KLoading dataset %s... done\n", prefix.c_str());
            return nullptr;
        }

        // Load the next chunk.
        if (!quiet) printf("\033[A\033[KLoading dataset %s... batch %u/%u (load)\n",
            prefix.c_str(), cur_batch, num_batches);
        std::string fname = prefix + "-" + std::to_string(cur_batch) + ".rb";

        // Load the RecordBatch into the default memory pool as a single blob
        // of data.
        std::shared_ptr<arrow::io::ReadableFile> file;
        arrow::Status status = arrow::io::ReadableFile::Open(fname, &file);
        if (!status.ok()) {
            throw std::runtime_error("ReadableFile::Open failed for " + fname + ": " + status.ToString());
        }
        std::shared_ptr<arrow::ipc::RecordBatchFileReader> reader;
        status = arrow::ipc::RecordBatchFileReader::Open(file, &reader);
        if (!status.ok()) {
            throw std::runtime_error("RecordBatchFileReader::Open failed for " + fname + ": " + status.ToString());
        }
        std::shared_ptr<arrow::RecordBatch> batch;
        status = reader->ReadRecordBatch(0, &batch);
        if (!status.ok()) {
            throw std::runtime_error("ReadRecordBatch() failed for " + fname + ": " + status.ToString());
        }

        // In order to make the buffers individually freeable and aligned, we
        // unfortunately need to copy the resulting RecordBatch entirely.
        if (!quiet) printf("\033[A\033[KLoading dataset %s... batch %u/%u (align)\n",
            prefix.c_str(), cur_batch, num_batches);
        std::vector<std::shared_ptr<arrow::ArrayData>> columns;
        for (int col_idx = 0; col_idx < batch->num_columns(); col_idx++) {
            std::shared_ptr<arrow::ArrayData> column = batch->column_data(col_idx);
            std::vector<std::shared_ptr<arrow::Buffer>> buffers;
            for (unsigned int buf_idx = 0; buf_idx < column->buffers.size(); buf_idx++) {
                std::shared_ptr<arrow::Buffer> in_buffer = column->buffers[buf_idx];
                if (!in_buffer) {
                    buffers.push_back(nullptr);
                    continue;
                }
                std::shared_ptr<arrow::Buffer> out_buffer;
                status = in_buffer->Copy(0, in_buffer->size(), &out_buffer);
                if (!status.ok()) {
                    throw std::runtime_error("Arrow buffer copy failed: " + status.ToString());
                }
                buffers.push_back(out_buffer);
            }
            columns.push_back(arrow::ArrayData::Make(column->type, column->length, buffers, column->null_count, column->offset));
        }
        batch = arrow::RecordBatch::Make(batch->schema(), batch->num_rows(), columns);

        // Transfer ownership to the caller.
        if (!quiet) printf("\033[A\033[KLoading dataset %s... batch %u/%u (xfer)\n",
            prefix.c_str(), cur_batch, num_batches);
        cur_batch++;
        return batch;

    }

    /**
     * Loads all (remaining) chunks into the given set of word matcher
     * implementations.
     */
    void load(std::vector<std::shared_ptr<WordMatch>> impls) {
        for (auto impl : impls) {
            impl->clear_chunks();
        }
        while (auto chunk = next()) {
            for (auto impl : impls) {
                impl->add_chunk(chunk);
            }
        }
    }

};

/**
 * Represents a search command for the hardware word matcher kernel.
 */
class HardwareWordMatchConfig {
public:
    uint32_t pattern_data[8];
    uint32_t search_config;

    HardwareWordMatchConfig(const WordMatchConfig &config) {
        char *pattern_chars = (char*)pattern_data;
        int first = 32 - config.pattern.length();
        if (first < 0) {
            throw std::runtime_error("search pattern is too long");
        }
        for (int i = 0; i < first; i++) {
            pattern_chars[i] = 0;
        }
        for (int i = first; i < 32; i++) {
            pattern_chars[i] = config.pattern[i - first];
        }

        search_config = (uint32_t)first;
        if (config.whole_words) {
            search_config |= 1 << 8;
        }
        search_config |= (uint32_t)config.min_matches << 16;
    }

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
 * Represents the statistics output of a word match kernel.
 */
class HardwareWordMatchStats {
public:
    unsigned int num_page_matches;
    unsigned int num_word_matches;
    unsigned int max_word_matches;
    unsigned int max_page_idx;
    std::string max_page_title;
    unsigned int cycle_count;

    HardwareWordMatchStats(AlveoBuffer &buffer, const HardwareWordMatchDataChunk &chunk) {

        // Read the buffer.
        unsigned int data[5];
        if (buffer.get_size() != sizeof(data)) {
            throw std::runtime_error("incorrect statistics buffer size");
        }
        buffer.read(&data);

        // Interpret the buffer.
        num_page_matches = data[0];
        num_word_matches = data[1];
        max_word_matches = data[2];
        max_page_idx = data[3];
        cycle_count = data[4];

        // Find the title of the page with the most matches.
        if (max_page_idx < chunk.num_rows) {
            const uint32_t *offsets = (const uint32_t*)chunk.arrow_title_offsets->data();
            uint32_t start = offsets[max_page_idx];
            uint32_t end = offsets[max_page_idx + 1];
            max_page_title = std::string((const char*)chunk.arrow_title_values->data() + start, end - start);
        } else {
            max_page_title = "<OUT-OF-RANGE>";
        }

    }
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

    // Input buffers.
    std::vector<HardwareWordMatchDataChunk> chunks;
    unsigned int current_chunk;

    // Result buffers.
    std::shared_ptr<AlveoBuffer> result_title_offset;
    std::shared_ptr<AlveoBuffer> result_title_values;
    std::shared_ptr<AlveoBuffer> result_matches;
    std::shared_ptr<AlveoBuffer> result_stats;

    std::shared_ptr<AlveoBuffer> arrow_to_alveo(
        AlveoKernelInstance &context, int bank, const std::shared_ptr<arrow::Buffer> &buffer)
    {
        return std::make_shared<AlveoBuffer>(context, buffer->size(), (void*)buffer->data(), bank);
    }

public:

    HardwareWordMatchKernel(const HardwareWordMatchKernel&) = delete;

    /**
     * Resets the dataset stored in device memory.
     */
    void clear_chunks() {
        chunks.clear();
        current_chunk = 0xFFFFFFFF;
    }

    HardwareWordMatchKernel(AlveoKernelInstance &context, int num_results = 32)
        : context(context), num_results(num_results)
    {

        // Detect which bank this kernel is connected to.
        for (bank = 0; bank < 4; bank++) {
            try {
                StdoutSuppressor x;
                AlveoBuffer test_buf(context, 4, bank);
                context.set_arg(0, test_buf.buffer);
                break;
            } catch (const std::runtime_error&) {
            }
        }

        // Create buffers for the results.
        result_title_offset = std::make_shared<AlveoBuffer>(
            context, CL_MEM_WRITE_ONLY, (num_results + 1) * 4, bank);
        result_title_values = std::make_shared<AlveoBuffer>(
            context, CL_MEM_WRITE_ONLY, (num_results + 1) * 256, bank);
        result_matches = std::make_shared<AlveoBuffer>(
            context, CL_MEM_WRITE_ONLY, (num_results + 1) * 4, bank);
        result_stats = std::make_shared<AlveoBuffer>(
            context, CL_MEM_WRITE_ONLY, 20, bank);

        // Set the kernel arguments that don't ever change.
        context.set_arg(4, (unsigned int)0);
        context.set_arg(8, result_title_offset->buffer);
        context.set_arg(9, result_title_values->buffer);
        context.set_arg(10, result_matches->buffer);
        context.set_arg(11, (unsigned int)num_results);
        context.set_arg(12, result_stats->buffer);

        // Reset the dataset.
        clear_chunks();
    }

    /**
     * Loads a recordbatch into the on-device OpenCL buffers for this instance.
     * Returns the chunk ID for the constructed chunk.
     */
    unsigned int add_chunk(const std::shared_ptr<arrow::RecordBatch> &batch) {

        HardwareWordMatchDataChunk chunk;
        chunk.arrow_title_offsets = batch->column_data(0)->buffers[1];
        chunk.arrow_title_values = batch->column_data(0)->buffers[2];
        chunk.title_offset = arrow_to_alveo(context, bank, batch->column_data(0)->buffers[1]);
        chunk.title_values = arrow_to_alveo(context, bank, batch->column_data(0)->buffers[2]);
        chunk.text_offset = arrow_to_alveo(context, bank, batch->column_data(1)->buffers[1]);
        chunk.text_values = arrow_to_alveo(context, bank, batch->column_data(1)->buffers[2]);
        chunk.num_rows = batch->num_rows();
        chunks.push_back(chunk);

        return chunks.size() - 1;
    }

    /**
     * Returns the number of loaded chunks.
     */
    unsigned int size() const {
        return chunks.size();
    }

    /**
     * Configures this instance with a search pattern and search configuration.
     */
    void configure(const HardwareWordMatchConfig &config) {

        // Configure the command-specific kernel arguments.
        context.set_arg(21, config.search_config);
        for (int i = 0; i < 8; i++) {
            context.set_arg(13 + i, config.pattern_data[i]);
        }

    }

private:

    /**
     * Runs this instance on a previously loaded chunk using the current
     * configuration.
     */
    cl_event enqueue_for_chunk_(unsigned int chunk) {

        if (chunk != current_chunk) {

            // Configure the chunk kernel arguments.
            context.set_arg(0, chunks[chunk].title_offset->buffer);
            context.set_arg(1, chunks[chunk].title_values->buffer);
            context.set_arg(2, chunks[chunk].text_offset->buffer);
            context.set_arg(3, chunks[chunk].text_values->buffer);
            context.set_arg(5, (unsigned int)chunks[chunk].num_rows / 3);
            context.set_arg(6, (unsigned int)(chunks[chunk].num_rows * 2) / 3);
            context.set_arg(7, (unsigned int)chunks[chunk].num_rows);

            // Remember which chunk we're configured for.
            current_chunk = chunk;

        }

        // Enqueue the kernel.
        cl_event event;
        cl_int err = clEnqueueTask(context.queue, context.kernel, 0, NULL, &event);
        if (err != CL_SUCCESS) {
            throw std::runtime_error("clEnqueueTask() failed");
        }
        return event;
    }

public:

    /**
     * Runs this instance on a previously loaded chunk using the current
     * configuration. Returns the event object for the chunk to be waited
     * on.
     */
    std::shared_ptr<AlveoEvents> enqueue_for_chunk(unsigned int chunk) {
        return std::make_shared<AlveoEvents>(enqueue_for_chunk_(chunk));

    }

    /**
     * Runs this instance on a previously loaded chunk using the current
     * configuration. Adds the event to an existing Alveo event object,
     */
    void enqueue_for_chunk(unsigned int chunk, AlveoEvents &events) {
        events.add(enqueue_for_chunk_(chunk));
    }

    /**
     * Loads the statistics for the most recent run.
     */
    HardwareWordMatchStats get_stats() {
        return HardwareWordMatchStats(*result_stats, chunks[current_chunk]);
    }

    /**
     * Loads the results for the most recent run into the given result buffer.
     */
    void get_results(WordMatchPartialResultsContainer &results) {

        // Read the statistics buffer.
        unsigned int data[4];
        result_stats->read(&data, 0, sizeof(data));

        // Interpret the statistics buffer.
        results.num_page_matches = data[0];
        results.num_word_matches = data[1];
        results.max_word_matches = data[2] >> 20;
        unsigned int max_page_idx = data[2] & 0xFFFFF;
        results.cycle_count = data[3];

        // Find the title of the page with the most matches.
        auto &chunk = chunks[current_chunk];
        if (max_page_idx < chunk.num_rows) {
            const uint32_t *offsets = (const uint32_t*)chunk.arrow_title_offsets->data();
            uint32_t start = offsets[max_page_idx];
            uint32_t end = offsets[max_page_idx + 1];
            results.cpp_max_page_title = std::string((const char*)chunk.arrow_title_values->data() + start, end - start);
        } else {
            results.cpp_max_page_title = "<OUT-OF-RANGE>";
        }

        // Determine how many valid match results we have in the result
        // buffers.
        unsigned int result_count = results.num_page_matches;
        if (result_count > num_results) result_count = num_results;

        // Read match count per page buffer.
        results.cpp_page_match_counts.resize(result_count);
        result_matches->read(
            results.cpp_page_match_counts.data(),
            0, result_count * 4);

        // Read title offset buffer.
        results.cpp_page_match_title_offsets.resize(result_count + 1);
        result_title_offset->read(
            results.cpp_page_match_title_offsets.data(),
            0, (result_count + 1) * 4);

        // Read title values buffer.
        results.cpp_page_match_title_values.resize(results.cpp_page_match_title_offsets.back());
        result_title_values->read(
            &results.cpp_page_match_title_values.front(),
            0, results.cpp_page_match_title_offsets.back());

        // Synchronize the results buffer.
        results.synchronize();

    }

    /**
     * Synchronously runs the kernel for the given chunk index, writing the
     * results (including execution time) to the given results buffer.
     */
    void execute_chunk(unsigned int chunk, WordMatchPartialResultsContainer &results) {
        auto start = std::chrono::high_resolution_clock::now();
        enqueue_for_chunk(chunk)->wait();
        get_results(results);
        auto elapsed = std::chrono::high_resolution_clock::now() - start;
        results.time_taken = std::chrono::duration_cast<std::chrono::microseconds>(elapsed).count();
    }

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

    /**
     * Constructs the word matcher from an xclbin prefix excluding the
     * `.[device].xclbin` suffix (this is chosen automatically), and the name
     * of the kernel in the xclbin file.
     */
    HardwareWordMatch(const std::string &bin_prefix, const std::string &kernel_name)
        : context(bin_prefix, kernel_name)
    {

        // Construct HardwareWordMatchKernel objects for each subdevice.
        for (auto instance : context.instances) {
            kernels.push_back(std::make_shared<HardwareWordMatchKernel>(*instance));
        }

    }

    /**
     * Resets the dataset stored in device memory.
     */
    virtual void clear_chunks() {
        for (auto kernel : kernels) {
            kernel->clear_chunks();
        }
        round_robin_state = 0;
        num_batches = 0;
    }

    /**
     * Adds the given chunk to the dataset stored in device memory.
     */
    virtual void add_chunk(const std::shared_ptr<arrow::RecordBatch> &batch) {
        round_robin_state %= kernels.size();
        kernels[round_robin_state]->add_chunk(batch);
        round_robin_state++;
        num_batches++;
    }

    /**
     * Runs the kernel with the given configuration.
     */
    virtual void execute(const WordMatchConfig &config) {

        // Generate the hardware configuration.
        HardwareWordMatchConfig hw_config(config);

        // Resize the results buffer.
        results.cpp_partial_results.resize(num_batches);

        // Start measuring execution time.
        auto start = std::chrono::high_resolution_clock::now();

        // Run the kernels.
        omp_set_dynamic(0);
        omp_set_num_threads(kernels.size());
        #pragma omp parallel for firstprivate(kernels)
        for (unsigned int i = 0; i < kernels.size(); i++) {
            kernels[i]->configure(hw_config);
            for (unsigned int j = 0; j < kernels[i]->size(); j++) {
                kernels[i]->execute_chunk(j, this->results.cpp_partial_results[j * kernels.size() + i]);
            }
        }

        // Combine the results.
        results.num_word_matches = 0;
        results.num_page_matches = 0;
        results.max_word_matches = 0;
        for (unsigned int i = 0; i < num_batches; i++) {
            results.num_word_matches += results.cpp_partial_results[i].num_word_matches;
            results.num_page_matches += results.cpp_partial_results[i].num_page_matches;
            if (results.cpp_partial_results[i].max_word_matches >= results.max_word_matches) {
                results.max_word_matches = results.cpp_partial_results[i].max_word_matches;
                results.max_page_title = results.cpp_partial_results[i].max_page_title;
            }
        }

        // Finish measuring execution time.
        auto elapsed = std::chrono::high_resolution_clock::now() - start;
        results.time_taken = std::chrono::duration_cast<std::chrono::microseconds>(elapsed).count();

        results.synchronize();

    }

};

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

    // Construct the managers for the desired word matcher implementations.
    std::vector<std::shared_ptr<WordMatch>> impls;

    impls.push_back(std::make_shared<HardwareWordMatch>(bin_prefix + "." + emu_mode, kernel_name));

    // Load the Wikipedia record batches and distribute them over the kernel
    // instances.
    WordMatchDatasetLoader(data_prefix).load(impls);

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
            return 0;
        }

        // Generate the implementation-agnostic configuration.
        WordMatchConfig config(pattern);

        impls[0]->execute(config);

        printf("\n%u pages matched & %u total matches within %.6fs\n",
            impls[0]->results.num_page_matches, impls[0]->results.num_word_matches,
            impls[0]->results.time_taken / 1000000.);
        if (impls[0]->results.max_word_matches) {
            printf("Best match is \"%s\", coming in at %u matches\n",
                impls[0]->results.max_page_title, impls[0]->results.max_word_matches);
        }

    }
}
