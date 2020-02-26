#pragma once

#include <inttypes.h>
#include <string>

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
    MmapFile(const std::string &filename);

    /**
     * Frees a memory-mapped file.
     */
    ~MmapFile();

    /**
     * Returns the pointer to the memory mapping.
     */
    const uint8_t *data() const;

    /**
     * Returns the size of the memory mapping.
     */
    const size_t size() const;

};

/**
 * XRT likes to spam error messages to stdout in addition to setting the OpenCL
 * result to the appropriate code. Unfortunately, there currently does not
 * appear to be a way to query bank connectivity for a kernel, so the only way
 * is to hardcode the connectivity or try until success. We opt for the latter.
 * To suppress the error messages we use this piece of work, which redirects
 * stdout to /dev/null for the lifetime of the object.
 */
class StdoutSuppressor {
private:
    int real_stdout;
public:
    StdoutSuppressor();
    ~StdoutSuppressor();
};

