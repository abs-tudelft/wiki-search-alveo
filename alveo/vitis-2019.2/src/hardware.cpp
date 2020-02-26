
#include "hardware.hpp"
#include <omp.h>
#include <mutex>
#include <iostream>

/**
 * Constructs a search command for the hardware word matcher kernel.
 */
HardwareWordMatchConfig::HardwareWordMatchConfig(const WordMatchConfig &config) {
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

std::shared_ptr<AlveoBuffer> HardwareWordMatchKernel::arrow_to_alveo(
    AlveoKernelInstance &context, int bank, const std::shared_ptr<arrow::Buffer> &buffer)
{
    return std::make_shared<AlveoBuffer>(context, buffer->size(), (void*)buffer->data(), bank);
}

/**
 * Resets the dataset stored in device memory.
 */
void HardwareWordMatchKernel::clear_chunks() {
    chunks.clear();
    current_chunk = 0xFFFFFFFF;
}

HardwareWordMatchKernel::HardwareWordMatchKernel(
    AlveoKernelInstance &context,
    float clock0,
    float clock1,
    unsigned int num_subkernels,
    int num_results
) :
    context(context),
    num_results(num_results),
    clock0(clock0),
    clock1(clock1),
    num_sub(num_subkernels)
{

    // Detect which bank this kernel is connected to.
    // TODO: the autodetection code below is broken in Vitis/recent XRT
    // versions, probably because the buffer upload is postponed. For now the
    // banks are hardcoded, but this is not very nice.
    /*for (bank = 0; bank < 4; bank++) {
        try {
            StdoutSuppressor x;
            AlveoBuffer test_buf(context, 4, bank);
            context.set_arg(0, test_buf.buffer);
            break;
        } catch (const std::runtime_error&) {
        }
    }*/
    switch (context.index) {
        case 0x0: bank = 0; break;
        case 0x1: bank = 0; break;
        case 0x2: bank = 0; break;
        case 0x3: bank = 0; break;
        case 0x4: bank = 0; break;
        case 0x5: bank = 1; break;
        case 0x6: bank = 1; break;
        case 0x7: bank = 1; break;
        case 0x8: bank = 1; break;
        case 0x9: bank = 1; break;
        case 0xA: bank = 3; break;
        case 0xB: bank = 3; break;
        case 0xC: bank = 3; break;
        case 0xD: bank = 3; break;
        case 0xE: bank = 3; break;
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

    // Set the kernel arguments that don't ever change. XRT prints inane
    // warnings about some kernels not being connected to some banks when
    // setting the parameters, which we suppress with the StdoutSuppressor.
    {
        StdoutSuppressor x;
        context.set_arg(4, (unsigned int)0);
        context.set_arg(5+num_sub, result_title_offset->buffer);
        context.set_arg(6+num_sub, result_title_values->buffer);
        context.set_arg(7+num_sub, result_matches->buffer);
        context.set_arg(8+num_sub, (unsigned int)num_results);
        context.set_arg(9+num_sub, result_stats->buffer);
    }

    // Reset the dataset.
    clear_chunks();
}

/**
 * Loads a recordbatch into the on-device OpenCL buffers for this instance.
 * Returns the chunk ID for the constructed chunk.
 */
unsigned int HardwareWordMatchKernel::add_chunk(const std::shared_ptr<arrow::RecordBatch> &batch) {

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
unsigned int HardwareWordMatchKernel::size() const {
    return chunks.size();
}

/**
 * Configures this instance with a search pattern and search configuration.
 */
void HardwareWordMatchKernel::configure(const HardwareWordMatchConfig &config) {

    // Configure the command-specific kernel arguments.
    context.set_arg(18+num_sub, config.search_config);
    for (int i = 0; i < 8; i++) {
        context.set_arg(10+num_sub + i, config.pattern_data[i]);
    }

}

/**
 * Runs this instance on a previously loaded chunk using the current
 * configuration.
 */
cl_event HardwareWordMatchKernel::enqueue_for_chunk_(unsigned int chunk) {

    if (chunk != current_chunk) {

        // Configure the chunk kernel arguments.
        context.set_arg(0, chunks[chunk].title_offset->buffer);
        context.set_arg(1, chunks[chunk].title_values->buffer);
        context.set_arg(2, chunks[chunk].text_offset->buffer);
        context.set_arg(3, chunks[chunk].text_values->buffer);
        for (unsigned int i = 1; i <= num_sub; i++) {
            context.set_arg(4+i, (unsigned int)(chunks[chunk].num_rows * i) / num_sub);
        }

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

/**
 * Runs this instance on a previously loaded chunk using the current
 * configuration. Returns the event object for the chunk to be waited
 * on.
 */
std::shared_ptr<AlveoEvents> HardwareWordMatchKernel::enqueue_for_chunk(unsigned int chunk) {
    return std::make_shared<AlveoEvents>(enqueue_for_chunk_(chunk));
}

/**
 * Runs this instance on a previously loaded chunk using the current
 * configuration. Adds the event to an existing Alveo event object,
 */
void HardwareWordMatchKernel::enqueue_for_chunk(unsigned int chunk, AlveoEvents &events) {
    events.add(enqueue_for_chunk_(chunk));
}

/**
 * Loads the results for the most recent run into the given result buffer.
 */
void HardwareWordMatchKernel::get_results(WordMatchPartialResultsContainer &results) {

    // Read the statistics buffer.
    unsigned int data[5];
    result_stats->read(&data, 0, sizeof(data));

    // Interpret the statistics buffer.
    results.num_page_matches = data[0];
    results.num_word_matches = data[1];
    results.max_word_matches = data[2];
    unsigned int max_page_idx = data[3];
    results.cycle_count = data[4];

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
void HardwareWordMatchKernel::execute_chunk(unsigned int chunk, WordMatchPartialResultsContainer &results) {
    auto start = std::chrono::high_resolution_clock::now();
    results.data_size = (unsigned long long)chunks[chunk].text_offset->get_size()
                      + (unsigned long long)chunks[chunk].text_values->get_size();
    results.clock_frequency = clock0;
    enqueue_for_chunk(chunk)->wait();
    get_results(results);
    auto elapsed = std::chrono::high_resolution_clock::now() - start;
    results.time_taken = std::chrono::duration_cast<std::chrono::microseconds>(elapsed).count();
}

/**
 * Constructs the word matcher from an xclbin prefix excluding the
 * `.[device].xclbin` suffix (this is chosen automatically), and the name
 * of the kernel in the xclbin file.
 */
HardwareWordMatch::HardwareWordMatch(
    const std::string &bin_prefix,
    const std::string &kernel_name,
    unsigned int num_subkernels,
    bool quiet
) :
    context(bin_prefix, kernel_name, quiet)
{

    // Construct HardwareWordMatchKernel objects for each subdevice.
    for (auto instance : context.instances) {
        kernels.push_back(std::make_shared<HardwareWordMatchKernel>(
            *instance, context.clock0, context.clock1, num_subkernels));
    }

}

/**
 * Resets the dataset stored in device memory.
 */
void HardwareWordMatch::clear_chunks() {
    for (auto kernel : kernels) {
        kernel->clear_chunks();
    }
    round_robin_state = 0;
    num_batches = 0;
}

/**
 * Adds the given chunk to the dataset stored in device memory.
 */
void HardwareWordMatch::add_chunk(const std::shared_ptr<arrow::RecordBatch> &batch) {
    round_robin_state %= kernels.size();
    kernels[round_robin_state]->add_chunk(batch);
    round_robin_state++;
    num_batches++;
}

/**
 * Runs the kernel with the given configuration.
 */
void HardwareWordMatch::execute(
    const WordMatchConfig &config,
    void (*progress)(void *user, const char *status), void *progress_user
) {

    if (progress) {
        std::string msg = "Running on hardware... completed 0/" + std::to_string(num_batches);
        progress(progress_user, msg.c_str());
    }

    // Generate the hardware configuration.
    HardwareWordMatchConfig hw_config(config);

    // Resize the results buffer.
    results.cpp_partial_results.resize(num_batches);

    // Start measuring execution time.
    auto start = std::chrono::high_resolution_clock::now();

    // Run the kernels.
    omp_set_dynamic(0);
    omp_set_num_threads(kernels.size());
    unsigned int chunks_complete = 0;
    static std::mutex progress_mutex;
    #pragma omp parallel for
    for (unsigned int i = 0; i < kernels.size(); i++) {
        kernels[i]->configure(hw_config);
        for (unsigned int j = 0; j < kernels[i]->size(); j++) {
            kernels[i]->execute_chunk(j, this->results.cpp_partial_results[j * kernels.size() + i]);
            if (progress) {
                std::lock_guard<std::mutex> lock(progress_mutex);
                chunks_complete++;
                std::string msg = "Running on hardware... completed " + std::to_string(chunks_complete) + "/" + std::to_string(num_batches);
                progress(progress_user, msg.c_str());
            }
        }
    }

    // Finish measuring execution time.
    auto elapsed = std::chrono::high_resolution_clock::now() - start;
    results.time_taken = std::chrono::duration_cast<std::chrono::microseconds>(elapsed).count();
    if (progress) {
        std::string msg = "Running on hardware... done";
        progress(progress_user, msg.c_str());
    }

    results.synchronize();

}
