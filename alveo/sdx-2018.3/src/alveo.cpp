
#include "alveo.hpp"
#include "xbutil.hpp"
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>

AlveoKernelInstance::AlveoKernelInstance(
    cl_device_id device,
    cl_program program,
    const std::string &kernel_name,
    unsigned int index
) :
    device(device),
    kernel_name(kernel_name),
    index(index)
{

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

AlveoKernelInstance::~AlveoKernelInstance() {
    clReleaseKernel(kernel);
    clReleaseCommandQueue(queue);
    clReleaseContext(context);
}

AlveoContext::AlveoContext(const std::string &bin_prefix, const std::string &kernel_name, bool quiet) {

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
    if (!quiet) printf("Platform:\n  Vendor: Xilinx\n  Name: %s\n", param);

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
        if (!quiet) printf("  Device %u: %s", i, param);
        if (device == NULL) {
            xclbin_fname = bin_prefix + "." + param + ".xclbin";
            if (device == NULL && access(xclbin_fname.c_str(), F_OK) != -1) {
                if (!quiet) printf(" <--");
                device = devices[i];
                device_index = i;
            }
        }
        if (!quiet) printf("\n");
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
    if (!quiet) printf("\nLoading binary %s... ", xclbin_fname.c_str());
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
    if (!quiet) printf("done\n");

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
            subdevices[i], program, kernel_name, i));
    }
    if (!quiet) printf("Found %u kernel instances.\n\n", num_subdevices);

    // Query the frequencies.
    XBUtilDumpInfo info;
    xbutil_dump(info, device_index);
    clock0 = info.clock0;
    clock1 = info.clock1;
    if (!quiet) printf("Frequencies are %.0f MHz (clock 0 & bus) and %.0f MHz (clock 1).\n\n", clock0, clock1);
}

AlveoContext::~AlveoContext() {
    instances.clear();
    clReleaseCommandQueue(queue);
    clReleaseProgram(program);
    clReleaseContext(context);
}

AlveoEvents::AlveoEvents() {
}

AlveoEvents::AlveoEvents(cl_event event) {
    add(event);
}

AlveoEvents::~AlveoEvents() {
    wait();
}

void AlveoEvents::add(cl_event event) {
    events.push_back(event);
}

void AlveoEvents::wait() {
    if (!events.size()) {
        return;
    }
    cl_int err = clWaitForEvents(events.size(), events.data());
    if (err != CL_SUCCESS) {
        throw std::runtime_error("clWaitForEvents() failed");
    }
    for (auto event : events) {
        clReleaseEvent(event);
    }
    events.clear();
}

void AlveoBuffer::mkhost(const void *data) {

    // Create a page-aligned region in physical memory for XDMA to use.
    fake_host_ptr = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (fake_host_ptr == MAP_FAILED) {
        throw std::runtime_error("mmap failed (" + std::to_string(errno) + ")");
    }

    // Copy the file data into this region.
    memcpy(fake_host_ptr, data, size);

}

void AlveoBuffer::mkbuf(cl_mem_flags flags, void *data, int bank) {
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

void AlveoBuffer::migrate() {
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

void AlveoBuffer::kill_host() {

    // Kill the physical memory usage on the host by overriding the mapping
    // with inaccessible memory.
    void *result = mmap(fake_host_ptr, size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    if (result != fake_host_ptr) {
        clReleaseMemObject(buffer);
        throw std::runtime_error("remapping mmap failed (" + std::to_string(errno) + ")");
    }

}

/**
 * Construct a buffer that can be read/written by the kernel and the host.
 */
AlveoBuffer::AlveoBuffer(AlveoKernelInstance &context, size_t size, int bank) : context(context), size(size) {
    fake_host_ptr = NULL;
    mkbuf(CL_MEM_READ_WRITE, NULL, bank);
    migrate();
}

/**
 * Construct a buffer that can be read/written by the host, with the given
 * flags for kernel read/write access etc..
 */
AlveoBuffer::AlveoBuffer(AlveoKernelInstance &context, cl_mem_flags flags, size_t size, int bank) : context(context), size(size) {
    fake_host_ptr = NULL;
    mkbuf(flags, NULL, bank);
    migrate();
}

/**
 * Construct an input buffer for the kernel, that can only be written once
 * but doesn't cost memory on the host. This is done by unmapping the
 * physical memory on the host after the initial copy.
 */
AlveoBuffer::AlveoBuffer(AlveoKernelInstance &context, size_t size, void *data, int bank) : context(context), size(size) {

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
AlveoBuffer::AlveoBuffer(AlveoKernelInstance &context, const MmapFile &fil, size_t offs, size_t size, int bank) : context(context), size(size) {

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

AlveoBuffer::~AlveoBuffer() {
    clReleaseMemObject(buffer);
    if (fake_host_ptr != NULL) {
        munmap(fake_host_ptr, size);
    }
}

/**
 * Writes data to the buffer. This is an async operation; the returned
 * AlveoEvents object is used to wait for completion. Completion is waited upon
 * either when the wait() function is explicitly called or when the object
 * is destroyed.
 */
std::shared_ptr<AlveoEvents> AlveoBuffer::write(const void *data) {
    if (fake_host_ptr != NULL) {
        throw std::runtime_error("cannot write to buffer, host ptr is fake");
    }
    cl_event event;
    cl_int err = clEnqueueWriteBuffer(
        context.queue, buffer, CL_FALSE, 0, size, data, 0, NULL, &event);
    if (err != CL_SUCCESS) {
        throw std::runtime_error("clEnqueueWriteBuffer() failed");
    }
    return std::make_shared<AlveoEvents>(event);
}

/**
 * Synchronously reads data from the buffer.
 */
void AlveoBuffer::read(void *data, size_t offset, ssize_t size) {
    if (fake_host_ptr != NULL) {
        throw std::runtime_error("cannot read from buffer, host ptr is fake");
    }
    size_t read_size = this->size;
    if (size >= 0) read_size = (size_t)size;
    if (read_size + offset > this->size) {
        throw std::runtime_error("offset + size out of range");
    }
    if (!read_size) {
        return;
    }
    cl_int err = clEnqueueReadBuffer(
        context.queue, buffer, CL_TRUE, offset, read_size, data, 0, NULL, NULL);
    if (err != CL_SUCCESS) {
        throw std::runtime_error("clEnqueueReadBuffer() failed");
    }
}

/**
 * Returns the size of the buffer.
 */
size_t AlveoBuffer::get_size() const {
    return size;
}
