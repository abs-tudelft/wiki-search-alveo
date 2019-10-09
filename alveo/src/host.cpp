
#include "xcl2.hpp"
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

/**
 * Manages a memory-mapped file.
 */
class MmapFile {
private:
    int fd;
    size_t siz;
    void *dat;

public:

    /**
     * Constructs a memory-mapped file.
     */
    MmapFile(const std::string &filename) {

        // Open the file.
        fd = open(filename.c_str(), O_RDONLY);
        if (fd < 0) {
            throw std::runtime_error("failed to open " + filename + " for reading");
        }

        // Get the size of the file.
        struct stat s;
        if (fstat(fd, &s) < 0) {
            close(fd);
            throw std::runtime_error("failed to stat " + filename);
        }
        siz = s.st_size;

        // Map the file.
        dat = mmap(0, siz, PROT_READ, MAP_SHARED, fd, 0);
        if (dat == MAP_FAILED) {
            close(fd);
            throw std::runtime_error("failed to mmap " + filename);
        }
    }

    /**
     * Frees a memory-mapped file.
     */
    ~MmapFile() {
        munmap(dat, siz);
        close(fd);
    }

    /**
     * Returns the pointer to the memory mapping.
     */
    const uint8_t *data() const {
        return (uint8_t*)dat;
    }

    /**
     * Returns the size of the memory mapping.
     */
    const size_t size() const {
        return siz;
    }

};

/**
 * Manages a kernel instance and its associated subcontext.
 */
class AlveoKernelInstance {
public:
    cl_device_id device;
    cl_context context;
    cl_command_queue queue;
    cl_kernel kernel;

    AlveoKernelInstance(cl_device_id device, cl_program program, const std::string &kernel_name) : device(device) {

        // Create a context.
        cl_int err;
        context = clCreateContext(
            0, 1, &device, NULL, NULL, &err);
        if (err != CL_SUCCESS || context == NULL) {
            throw std::runtime_error("clCreateContext() failed");
        }

        // Create a command queue.
        queue = clCreateCommandQueue(
            context, device, 0, &err);
        if (err != CL_SUCCESS || context == NULL) {
            clReleaseContext(context);
            throw std::runtime_error("clCreateCommandQueue() failed");
        }

        // Create the kernel.
        kernel = clCreateKernel(
            program, kernel_name.c_str(), &err);
        if (err != CL_SUCCESS || context == NULL) {
            clReleaseCommandQueue(queue);
            clReleaseContext(context);
            throw std::runtime_error("clCreateKernel() failed");
        }

    }

    ~AlveoKernelInstance() {
        clReleaseKernel(kernel);
        clReleaseCommandQueue(queue);
        clReleaseContext(context);
    }

    template <typename T>
    void set_arg(int i, T value) {
        cl_int err = clSetKernelArg(kernel, i, sizeof(T), &value);
        if (err != CL_SUCCESS) {
            throw std::runtime_error(
                "clSetKernelArg(" + std::to_string(i) +
                ") failed for obj of size " + std::to_string(sizeof(T)));
        }
    }

};

/**
 * Manages an Alveo OpenCL context.
 */
class AlveoContext {
public:
    cl_context context;
    cl_program program;
    cl_command_queue queue;
    std::vector<std::shared_ptr<AlveoKernelInstance>> instances;

    AlveoContext(const std::string &bin_prefix, const std::string &kernel_name) {

        // Enumerate platforms.
        cl_platform_id platforms[16];
        cl_uint num_platforms;
        cl_int err = clGetPlatformIDs(16, platforms, &num_platforms);
        if (err != CL_SUCCESS) {
            throw std::runtime_error("clGetPlatformIDs() failed");
        }

        // Look for the Xilinx platform.
        cl_platform_id platform = NULL;
        char param[65];
        param[64] = 0;
        for (unsigned int i = 0; i < num_platforms; i++) {
            err = clGetPlatformInfo(
                platforms[i], CL_PLATFORM_VENDOR, 64, (void*)param, NULL);
            if (err != CL_SUCCESS) {
                throw std::runtime_error("clGetPlatformInfo(vendor) failed");
            }
            if (strcmp(param, "Xilinx") == 0) {
                platform = platforms[i];
                break;
            }
        }
        if (platform == NULL) {
            throw std::runtime_error("failed to find Xilinx platform ID");
        }
        err = clGetPlatformInfo(
            platform, CL_PLATFORM_NAME, 64, (void*)param, NULL);
        if (err != CL_SUCCESS) {
            throw std::runtime_error("clGetPlatformInfo(name) failed");
        }
        printf("Platform:\n  Vendor: Xilinx\n  Name: %s\n", param);

        // Enumerate devices in platform.
        cl_device_id devices[16];  // compute device id
        cl_uint num_devices;
        err = clGetDeviceIDs(
            platform, CL_DEVICE_TYPE_ACCELERATOR, 16, devices, &num_devices);
        if (err != CL_SUCCESS) {
            throw std::runtime_error("clGetDeviceIDs() failed");
        }
        if (num_devices == 0) {
            throw std::runtime_error("no devices in Xilinx platform");
        }

        // Select an accelerator that we have an xclbin file for.
        cl_device_id device = NULL;
        std::string xclbin_fname;
        for (unsigned int i = 0; i < num_devices; i++) {
            err = clGetDeviceInfo(devices[i], CL_DEVICE_NAME, 64, param, 0);
            if (err != CL_SUCCESS) {
                throw std::runtime_error("clGetDeviceInfo(name) failed");
            }
            printf("  Device %u: %s", i, param);
            if (device == NULL) {
                xclbin_fname = bin_prefix + ".hw." + param + ".xclbin";
                if (device == NULL && access(xclbin_fname.c_str(), F_OK) != -1) {
                    printf(" <--");
                    device = devices[i];
                }
            }
            printf("\n");
        }
        if (device == NULL) {
            throw std::runtime_error("no accelerator with corresponding xclbin found");
        }

        // Create a context.
        context = clCreateContext(0, 1, &device, NULL, NULL, &err);
        if (err != CL_SUCCESS || context == NULL) {
            throw std::runtime_error("clCreateContext() failed");
        }

        // Load the binary.
        printf("\nLoading binary %s... ", xclbin_fname.c_str());
        fflush(stdout);
        MmapFile xclbin(xclbin_fname);
        const size_t size = xclbin.size();
        const unsigned char *binary = (const unsigned char *)xclbin.data();
        program = clCreateProgramWithBinary(
            context, 1, &device, &size, &binary, NULL, &err);
        if (err != CL_SUCCESS || program == NULL) {
            clReleaseContext(context);
            throw std::runtime_error("clCreateProgramWithBinary() failed");
        }
        err = clBuildProgram(program, 0, NULL, NULL, NULL, NULL);
        if (err != CL_SUCCESS) {
            clReleaseProgram(program);
            clReleaseContext(context);
            throw std::runtime_error("clBuildProgram() failed");
        }
        printf("done\n");

        // Create a command queue.
        queue = clCreateCommandQueue(
            context, device, 0, &err);
        if (err != CL_SUCCESS || context == NULL) {
            clReleaseProgram(program);
            clReleaseContext(context);
            throw std::runtime_error("clCreateCommandQueue() failed");
        }

        // Partition into subdevices.
        cl_uint num_subdevices;
        cl_device_partition_property part_props[3] = {
            CL_DEVICE_PARTITION_EQUALLY, 1, 0};
        err = clCreateSubDevices(device, part_props, 0, NULL, &num_subdevices);
        if (err != CL_SUCCESS) {
            clReleaseCommandQueue(queue);
            clReleaseProgram(program);
            clReleaseContext(context);
            throw std::runtime_error("first clCreateSubDevices() failed");
        }
        std::vector<cl_device_id> subdevices(num_subdevices);
        err = clCreateSubDevices(
            device, part_props, num_subdevices, subdevices.data(), NULL);
        if (err != CL_SUCCESS) {
            clReleaseCommandQueue(queue);
            clReleaseProgram(program);
            clReleaseContext(context);
            throw std::runtime_error("second clCreateSubDevices() failed");
        }
        for (unsigned int i = 0; i < num_subdevices; i++) {
            instances.push_back(std::make_shared<AlveoKernelInstance>(
                subdevices[i], program, kernel_name));
        }
        printf("Found %u kernel instances\n", num_subdevices);


    }

    ~AlveoContext() {
        instances.clear();
        clReleaseCommandQueue(queue);
        clReleaseProgram(program);
        clReleaseContext(context);
    }

};

/**
 * Manages an OpenCL event.
 */
class Event {
private:
    cl_event event;

public:

    Event(cl_event event) : event(event) {
    }

    ~Event() {
        wait();
        clReleaseEvent(event);
    }

    void wait() {
        cl_int err = clWaitForEvents(1, &event);
        if (err != CL_SUCCESS) {
            throw std::runtime_error("clWaitForEvents() failed");
        }
    }
};

/**
 * Manages a buffer on the Alveo.
 */
class AlveoBuffer {
private:
    AlveoKernelInstance &context;
    void *fake_host_ptr;
    size_t size;
    cl_mem_ext_ptr_t ext;

public:
    cl_mem buffer;

private:

    void mkhost(const void *data) {

        // Create a page-aligned region in physical memory for XDMA to use.
        fake_host_ptr = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (fake_host_ptr == MAP_FAILED) {
            throw std::runtime_error("mmap failed (" + std::to_string(errno) + ")");
        }

        // Copy the file data into this region.
        memcpy(fake_host_ptr, data, size);

    }

    void mkbuf(cl_mem_flags flags, void *data, int bank) {
        ext.flags = bank | XCL_MEM_TOPOLOGY;
        ext.obj = data;
        ext.param = 0;
        flags |= CL_MEM_EXT_PTR_XILINX;
        if (data != NULL) {
            flags |= CL_MEM_USE_HOST_PTR;
        }

        cl_int err;
        buffer = clCreateBuffer(context.context, flags, size, &ext, &err);
        if (err != CL_SUCCESS || buffer == NULL) {
            throw std::runtime_error("clCreateBuffer() failed");
        }
    }

    void migrate() {
        cl_event event;
        cl_int err = clEnqueueMigrateMemObjects(context.queue, 1, &buffer, 0, 0, NULL, &event);
        if (err != CL_SUCCESS) {
            throw std::runtime_error("clEnqueueMigrateMemObjects() failed");
        }

        err = clWaitForEvents(1, &event);
        if (err != CL_SUCCESS) {
            clReleaseEvent(event);
            throw std::runtime_error("clWaitForEvents() failed");
        }

        clReleaseEvent(event);
    }

    void kill_host() {

        // Kill the physical memory usage on the host by overriding the mapping
        // with inaccessible memory.
        void *result = mmap(fake_host_ptr, size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
        if (result != fake_host_ptr) {
            clReleaseMemObject(buffer);
            throw std::runtime_error("remapping mmap failed (" + std::to_string(errno) + ")");
        }

    }

public:

    /**
     * Construct a buffer that can be read/written by the kernel and the host.
     */
    AlveoBuffer(AlveoKernelInstance &context, size_t size, int bank) : context(context), size(size) {
        fake_host_ptr = NULL;
        mkbuf(CL_MEM_READ_WRITE, NULL, bank);
        migrate();
    }

    /**
     * Construct a buffer that can be read/written by the host, with the given
     * flags for kernel read/write access etc..
     */
    AlveoBuffer(AlveoKernelInstance &context, cl_mem_flags flags, size_t size, int bank) : context(context), size(size) {
        fake_host_ptr = NULL;
        mkbuf(flags, NULL, bank);
        migrate();
    }

    /**
     * Construct an input buffer for the kernel, that can only be written once
     * but doesn't cost memory on the host. This is done by unmapping the
     * physical memory on the host after the initial copy.
     */
    AlveoBuffer(AlveoKernelInstance &context, size_t size, void *data, int bank) : context(context), size(size) {

        // Create a page-aligned region in physical memory for XDMA to use and
        // copy the file to it.
        mkhost(data);

        // Create the buffer from this region.
        mkbuf(CL_MEM_READ_ONLY, fake_host_ptr, bank);

        // Ensure that it is migrated to the device.
        migrate();

        // Kill the physical memory usage.
        kill_host();

    }

    /**
     * Construct an input buffer for the kernel from an mmap'd file, that can
     * only be written once but doesn't cost memory on the host. This is done
     * by unmapping the * physical memory on the host after the initial copy.
     */
    AlveoBuffer(AlveoKernelInstance &context, const MmapFile &fil, size_t offs, size_t size, int bank) : context(context), size(size) {

        // Create a page-aligned region in physical memory for XDMA to use and
        // copy the file to it.
        mkhost(fil.data() + offs);

        // Create the buffer from this region.
        mkbuf(CL_MEM_READ_ONLY, fake_host_ptr, bank);

        // Ensure that it is migrated to the device.
        migrate();

        // Kill the physical memory usage.
        kill_host();

    }

    ~AlveoBuffer() {
        clReleaseMemObject(buffer);
        if (fake_host_ptr != NULL) {
            munmap(fake_host_ptr, size);
        }
    }

    /**
     * Writes data to the buffer. This is an async operation; the returned
     * Event object is used to wait for completion. Completion is waited upon
     * either when the wait() function is explicitly called or when the object
     * is destroyed.
     */
    std::shared_ptr<Event> write(const void *data) {
        if (fake_host_ptr != NULL) {
            throw std::runtime_error("cannot write to buffer, host ptr is fake");
        }
        cl_event event;
        cl_int err = clEnqueueWriteBuffer(
            context.queue, buffer, CL_FALSE, 0, size, data, 0, NULL, &event);
        if (err != CL_SUCCESS) {
            throw std::runtime_error("clEnqueueWriteBuffer() failed");
        }
        return std::make_shared<Event>(event);
    }

    /**
     * Synchronously reads data from the buffer.
     */
    void read(void *data) {
        if (fake_host_ptr != NULL) {
            throw std::runtime_error("cannot read from buffer, host ptr is fake");
        }
        cl_int err = clEnqueueReadBuffer(
            context.queue, buffer, CL_TRUE, 0, size, data, 0, NULL, NULL);
        if (err != CL_SUCCESS) {
            throw std::runtime_error("clEnqueueReadBuffer() failed");
        }
    }

    /**
     * Returns the size of the buffer.
     */
    size_t get_size() const {
        return size;
    }

};

/**
 * Represents a search command for the word matcher kernel.
 */
class WordMatchConfig {
public:

    // C++-friendly argument form.
    std::string pattern;
    bool whole_words;
    uint16_t min_matches;

    // Kernel-friendly argument form.
    uint32_t pattern_data[8];
    uint32_t search_config;

    WordMatchConfig(const std::string &pattern, bool whole_words = false, uint16_t min_matches = 1)
        : pattern(pattern), whole_words(whole_words), min_matches(min_matches)
    {
        char *pattern_chars = (char*)pattern_data;
        int first = 32 - pattern.length();
        if (first < 0) {
            throw std::runtime_error("search pattern is too long");
        }
        for (int i = 0; i < first; i++) {
            pattern_chars[i] = 0;
        }
        for (int i = first; i < 32; i++) {
            pattern_chars[i] = pattern[i - first];
        }

        search_config = (uint32_t)first;
        if (whole_words) {
            search_config |= 1 << 8;
        }
        search_config |= (uint32_t)min_matches << 16;
    }

};

/**
 * Represents the statistics output of a word match kernel.
 */
class WordMatchStats {
public:
    unsigned int num_page_matches;
    unsigned int num_word_matches;
    unsigned int max_word_matches;
    unsigned int max_page_idx;
    unsigned int cycle_count;

    WordMatchStats(AlveoBuffer &buffer) {

        // Read the buffer.
        unsigned int data[4];
        if (buffer.get_size() != sizeof(data)) {
            throw std::runtime_error("incorrect statistics buffer size");
        }
        buffer.read(&data);

        // Interpret the buffer.
        num_page_matches = data[0];
        num_word_matches = data[1];
        max_word_matches = data[2] >> 20;
        max_page_idx = data[2] & 0xFFFFF;
        cycle_count = data[3];

    }
};

/**
 * Manages a word matcher kernel, operating on a fixed record batch that is
 * only loaded once.
 */
class WordMatch {
private:

    AlveoKernelInstance &context;
    unsigned int num_results;

    // Input buffers.
    std::shared_ptr<AlveoBuffer> title_offset;
    std::shared_ptr<AlveoBuffer> title_values;
    std::shared_ptr<AlveoBuffer> text_offset;
    std::shared_ptr<AlveoBuffer> text_values;

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

    WordMatch(AlveoKernelInstance &context, int bank, const std::string &fname, int num_results = 32)
        : context(context), num_results(num_results)
    {

        // Load the record batch.
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

        // Push the record batch to the Alveo memory.
        title_offset = arrow_to_alveo(context, bank, batch->column_data(0)->buffers[1]);
        title_values = arrow_to_alveo(context, bank, batch->column_data(0)->buffers[2]);
        text_offset = arrow_to_alveo(context, bank, batch->column_data(1)->buffers[1]);
        text_values = arrow_to_alveo(context, bank, batch->column_data(1)->buffers[2]);

        // Create buffers for the results.
        result_title_offset = std::make_shared<AlveoBuffer>(
            context, CL_MEM_WRITE_ONLY, (num_results + 1) * 4, bank);
        result_title_values = std::make_shared<AlveoBuffer>(
            context, CL_MEM_WRITE_ONLY, (num_results + 1) * 64, bank);
        result_matches = std::make_shared<AlveoBuffer>(
            context, CL_MEM_WRITE_ONLY, (num_results + 1) * 4, bank);
        result_stats = std::make_shared<AlveoBuffer>(
            context, CL_MEM_WRITE_ONLY, 16, bank);

        // Configure the non-changing kernel arguments.
        context.set_arg(0, title_offset->buffer);
        context.set_arg(1, title_values->buffer);
        context.set_arg(2, text_offset->buffer);
        context.set_arg(3, text_values->buffer);
        context.set_arg(4, (unsigned int)0);
        context.set_arg(5, (unsigned int)batch->num_rows());
        context.set_arg(6, result_title_offset->buffer);
        context.set_arg(7, result_title_values->buffer);
        context.set_arg(8, result_matches->buffer);
        context.set_arg(9, (unsigned int)num_results);
        context.set_arg(10, result_stats->buffer);

    }

    std::shared_ptr<Event> invoke(const WordMatchConfig &cmd) {

        // Configure the command-specific kernel arguments.
        context.set_arg(11, cmd.search_config);
        for (int i = 0; i < 8; i++) {
            context.set_arg(12 + i, cmd.pattern_data[i]);
        }

        // Enqueue the kernel.
        cl_event event;
        cl_int err = clEnqueueTask(context.queue, context.kernel, 0, NULL, &event);
        if (err != CL_SUCCESS) {
            throw std::runtime_error("clEnqueueTask() failed");
        }
        return std::make_shared<Event>(event);

    }

    WordMatchStats get_stats() {
        return WordMatchStats(*result_stats);
    }

};

int main(int argc, char **argv) {

    AlveoContext context("../../fletcher-alveo-demo-8/alveo/xclbin-kapot/word_match", "krnl_word_match_rtl");
    //AlveoContext context("xclbin/word_match", "krnl_word_match_rtl");
    //AlveoContext context("../../fletcher-alveo-demo-4/alveo/xclbin/word_match", "krnl_word_match_rtl");

    // Initialize the kernel instances with Wikipedia record batches.
    std::vector<std::shared_ptr<WordMatch>> matchers;
    for (unsigned int i = 0; i < context.instances.size(); i++) {
        int bank;
        if (context.instances.size() == 8) {
            if (i < 3) {
                bank = 0;
            } else if (i < 5) {
                bank = 1;
            } else {
                bank = 3;
            }
        } else if (context.instances.size() == 12) {
            bank = 1;
        } else {
            if (i < 15) {
                bank = 0;
            } else if (i < 20) {
                bank = 1;
            } else {
                bank = 3;
            }
        }
        printf("pushing data for word matcher %d to DDR bank %d...\n", i, bank);
        matchers.push_back(std::make_shared<WordMatch>(
            *context.instances[i], bank,
            "/work/shared/fletcher-alveo/simplewiki-" + std::to_string(i) + ".rb"));
    }

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

        WordMatchConfig cmd(pattern);

        // Enqueue kernel runs.
        std::vector<std::shared_ptr<Event>> events;
        for (unsigned int i = 0; i < matchers.size(); i++) {
            printf("queue matcher %d...\n", i);
            events.push_back(matchers[i]->invoke(cmd));
        }

        // Wait for completion on all kernels.
        printf("wait for matchers...\n");
        events.clear();

        // Print stats.
        for (unsigned int i = 0; i < matchers.size(); i++) {
            auto stats = matchers[i]->get_stats();
            printf("matcher %2d: %5u pages matched & %5u total matches within %u cycles (= %.6fs at 200MHz).\n",
                i, stats.num_page_matches, stats.num_word_matches, stats.cycle_count, stats.cycle_count / 200000000.);
        }

    }
}
