
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
 * Represents an input record batch for the word matcher.
 */
class WordMatchDataset {
private:
    std::vector<std::shared_ptr<arrow::RecordBatch>> chunks;

public:

    /**
     * Loads a single record batch file and appends it to this dataset. No
     * prints.
     */
    void push_chunk(const std::string &fname) {

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

        // Push the copied RecordBatch.
        chunks.push_back(batch);
    }

    /**
     * Clears all the chunks out of this dataset.
     */
    void clear() {
        chunks.clear();
    }

    /**
     * Returns the number of loaded chunks.
     */
    unsigned int size() const {
        return chunks.size();
    }

    /**
     * Returns the record batch for the given chunk index for the hardware
     * implementation.
     */
    std::shared_ptr<arrow::RecordBatch> get_chunk(int index = -1) {
        if (index < 0) {
            return chunks.back();
        } else {
            return chunks[index];
        }
    }

    /**
     * Returns the entire dataset as an arrow table for the software
     * implementation.
     */
    std::shared_ptr<arrow::Table> as_table() {
        std::shared_ptr<arrow::Table> table;
        arrow::Status status = arrow::Table::FromRecordBatches(chunks, &table);
        if (!status.ok()) {
            throw std::runtime_error("Table::FromRecordBatches failed: " + status.ToString());
        }
        return table;
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
 * Class used internally by HardwareWordMatch to keep track of the buffers for a given
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
class HardwareWordMatch {
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

    HardwareWordMatch(const HardwareWordMatch&) = delete;

    HardwareWordMatch(AlveoKernelInstance &context, int num_results = 32)
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

        current_chunk = 0xFFFFFFFF;
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

    // Create the context.
    AlveoContext context(bin_prefix + "." + emu_mode, kernel_name);

    // Construct HardwareWordMatch objects for each subdevice.
    std::vector<std::shared_ptr<HardwareWordMatch>> matchers;
    for (auto instance : context.instances) {
        matchers.push_back(std::make_shared<HardwareWordMatch>(*instance));
    }

    WordMatchDataset dataset;

    // Load the Wikipedia record batches and distribute them over the kernel
    // instances.
    unsigned int num_batches = 0;
    for (;; num_batches++) {
        std::string batch_filename = data_prefix + "-" + std::to_string(num_batches) + ".rb";
        if (access(batch_filename.c_str(), F_OK) == -1) {
            break;
        }
    }
    if (!num_batches) {
        throw std::runtime_error("no record batches found for prefix " + data_prefix);
    }
    dataset.clear();
    printf("\n");
    for (unsigned int batch = 0, matcher = 0; batch < num_batches; batch++, matcher++, matcher %= matchers.size()) {

        // Load chunk.
        printf("\033[A\033[KLoading dataset %s... batch %u/%u (load)\n",
            data_prefix.c_str(), batch, num_batches);
        dataset.push_chunk(data_prefix + "-" + std::to_string(batch) + ".rb");

        // Transfer to device.
        printf("\033[A\033[KLoading dataset %s... batch %u/%u (xfer to %u)\n",
            data_prefix.c_str(), batch, num_batches, matcher);
        matchers[matcher]->add_chunk(dataset.get_chunk());

        // Save memory when software runs are not needed by freeing the article
        // text buffers.
        printf("\033[A\033[KLoading dataset %s... batch %u/%u (free)\n",
           data_prefix.c_str(), batch, num_batches);
        dataset.clear();

    }
    printf("\033[A\033[KLoading dataset %s... done\n", data_prefix.c_str());

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

        WordMatchConfig config(pattern);
        HardwareWordMatchConfig hw_config(config);

//         // Enqueue kernel runs.
//         AlveoEvents events;
//         for (unsigned int i = 0; i < matchers.size(); i++) {
//             if (!matchers[i]->size()) continue;
//             printf("queue matcher %d...\n", i);
//             matchers[i]->configure(hw_config);
//             matchers[i]->enqueue_for_chunk(0), events);
//         }
//
//         // Wait for completion on all kernels.
//         printf("wait for matchers...\n");
//         events.wait();

        omp_set_dynamic(0);
        omp_set_num_threads(matchers.size());
        #pragma omp parallel for firstprivate(matchers)
        for (unsigned int i = 0; i < matchers.size(); i++) {
            if (!matchers[i]->size()) continue;
            int tid = omp_get_thread_num();
            printf("Hello world from omp thread %d\n", tid);
            matchers[i]->configure(hw_config);
            matchers[i]->enqueue_for_chunk(0)->wait();
        }

        // Print stats.
        for (unsigned int i = 0; i < matchers.size(); i++) {
            if (!matchers[i]->size()) continue;
            auto stats = matchers[i]->get_stats();
            printf("matcher %2d: %5u pages matched & %5u total matches within %u cycles (= %.6fs at 200MHz).\n",
                i, stats.num_page_matches, stats.num_word_matches, stats.cycle_count, stats.cycle_count / 200000000.);
            if (stats.max_word_matches) {
                printf("  best match is \"%s\", coming in at %u matches\n",
                    stats.max_page_title.c_str(), stats.max_word_matches);
            }
        }

    }
}
