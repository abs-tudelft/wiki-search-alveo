#pragma once

#include "utils.hpp"
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
 * Manages a kernel instance and its associated OpenCL (sub)context and queue.
 */
class AlveoKernelInstance {
public:
    cl_device_id device;
    cl_context context;
    cl_command_queue queue;
    cl_kernel kernel;

    AlveoKernelInstance(const AlveoKernelInstance&) = delete;
    AlveoKernelInstance(cl_device_id device, cl_program program, const std::string &kernel_name);
    ~AlveoKernelInstance();

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
 * Manages an Alveo OpenCL device context.
 */
class AlveoContext {
public:
    cl_context context;
    cl_program program;
    cl_command_queue queue;
    std::vector<std::shared_ptr<AlveoKernelInstance>> instances;

    AlveoContext(const AlveoContext&) = delete;
    AlveoContext(const std::string &bin_prefix, const std::string &kernel_name);
    ~AlveoContext();

};

/**
 * Manages an OpenCL event.
 */
class AlveoEvents {
private:
    std::vector<cl_event> events;

public:
    AlveoEvents(const AlveoEvents&) = delete;
    AlveoEvents();
    AlveoEvents(cl_event event);
    ~AlveoEvents();
    void add(cl_event event);
    void wait();

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

    void mkhost(const void *data);
    void mkbuf(cl_mem_flags flags, void *data, int bank);
    void migrate();
    void kill_host();

public:

    AlveoBuffer(const AlveoBuffer&) = delete;

    /**
     * Construct a buffer that can be read/written by the kernel and the host.
     */
    AlveoBuffer(AlveoKernelInstance &context, size_t size, int bank);

    /**
     * Construct a buffer that can be read/written by the host, with the given
     * flags for kernel read/write access etc..
     */
    AlveoBuffer(AlveoKernelInstance &context, cl_mem_flags flags, size_t size, int bank);

    /**
     * Construct an input buffer for the kernel, that can only be written once
     * but doesn't cost memory on the host. This is done by unmapping the
     * physical memory on the host after the initial copy.
     */
    AlveoBuffer(AlveoKernelInstance &context, size_t size, void *data, int bank);

    /**
     * Construct an input buffer for the kernel from an mmap'd file, that can
     * only be written once but doesn't cost memory on the host. This is done
     * by unmapping the * physical memory on the host after the initial copy.
     */
    AlveoBuffer(AlveoKernelInstance &context, const MmapFile &fil, size_t offs, size_t size, int bank);

    ~AlveoBuffer();

    /**
     * Writes data to the buffer. This is an async operation; the returned
     * AlveoEvents object is used to wait for completion. Completion is waited upon
     * either when the wait() function is explicitly called or when the object
     * is destroyed.
     */
    std::shared_ptr<AlveoEvents> write(const void *data);

    /**
     * Synchronously reads data from the buffer.
     */
    void read(void *data, size_t offset=0, ssize_t size=-1);

    /**
     * Returns the size of the buffer.
     */
    size_t get_size() const;

};
