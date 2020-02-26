
#include "utils.hpp"
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <stdexcept>

/**
 * Constructs a memory-mapped file.
 */
MmapFile::MmapFile(const std::string &filename) {

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
MmapFile::~MmapFile() {
    munmap(dat, siz);
    close(fd);
}

/**
 * Returns the pointer to the memory mapping.
 */
const uint8_t *MmapFile::data() const {
    return (uint8_t*)dat;
}

/**
 * Returns the size of the memory mapping.
 */
const size_t MmapFile::size() const {
    return siz;
}

StdoutSuppressor::StdoutSuppressor() {
    fflush(stdout);
    real_stdout = dup(1);
    int dev_null = open("/dev/null", O_WRONLY);
    dup2(dev_null, 1);
    close(dev_null);
}

StdoutSuppressor::~StdoutSuppressor() {
    fflush(stdout);
    dup2(real_stdout, 1);
    close(real_stdout);
}
