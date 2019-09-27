/**********
Copyright (c) 2018, Xilinx, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
may be used to endorse or promote products derived from this software
without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**********/
#include "xcl2.hpp"
#include <vector>

#include <arrow/api.h>
#include <arrow/io/api.h>
#include <arrow/ipc/api.h>

#define DATA_SIZE 256

int main(int argc, char **argv) {
    if (argc != 3) {
        std::cout << "Usage: " << argv[0] << " <XCLBIN File>" << " <RECORDBATCH File> " << std::endl;
        return EXIT_FAILURE;
    }

    std::string binaryFile = argv[1];
    std::string recordbatchFile = argv[2];

    arrow::Status status;
    std::shared_ptr<arrow::io::ReadableFile> file;
    std::shared_ptr<arrow::ipc::RecordBatchFileReader> reader;
    std::shared_ptr<arrow::RecordBatch> batch;

    status = arrow::io::ReadableFile::Open(recordbatchFile, &file);
    status = arrow::ipc::RecordBatchFileReader::Open(file, &reader);

    //std::cout << reader->num_record_batches() << std::endl;
    status = reader->ReadRecordBatch(0, &batch);
    //std::cout << batch->num_rows() << std::endl;
    //std::cout << reader->schema()->ToString() << std::endl;

    std::shared_ptr<arrow::ArrayData> titleData = batch->column_data(0);
    std::shared_ptr<arrow::ArrayData> textData = batch->column_data(1);

    //std::cout << titleData->length << std::endl;
    //std::cout << textData->length << std::endl;

    std::cout << titleData->buffers.size() << std::endl;
    //std::cout << (char*)(titleData->buffers[2]->data()) << std::endl;
    //std::cout << (char*)(textData->buffers[2]->data()) << std::endl;

    cl_int err;

    // TODO: used to pass valid pointers for the result table; remove me
    int dummy = 0;

    int first_idx = 0;
    int last_idx = batch->num_rows();

    //OPENCL HOST CODE AREA START
    //Create Program and Kernel
    auto devices = xcl::get_xil_devices();
    auto device = devices[0];

    OCL_CHECK(err, cl::Context context(device, NULL, NULL, NULL, &err));
    OCL_CHECK(
        err,
        cl::CommandQueue q(context, device, CL_QUEUE_PROFILING_ENABLE, &err));
    auto device_name = device.getInfo<CL_DEVICE_NAME>();

    auto fileBuf = xcl::read_binary_file(binaryFile);
    cl::Program::Binaries bins{{fileBuf.data(), fileBuf.size()}};
    devices.resize(1);
    OCL_CHECK(err, cl::Program program(context, devices, bins, NULL, &err));
    
    OCL_CHECK(err, cl::Kernel krnl_word_match(program, "krnl_word_match_rtl", &err));

    //std::cout << titleData->buffers[1]->size() << std::endl;
    //printf("0x%016llX\n", titleData->buffers[1]->data());

    // Allocate input buffers.
    OCL_CHECK(err, cl::Buffer buffer_title_offs(
        context,
        CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY,
        titleData->buffers[1]->size(),
        (void*)titleData->buffers[1]->data(),
        &err));

    OCL_CHECK(err, cl::Buffer buffer_title_val(
        context,
        CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY,
        titleData->buffers[2]->size(),
        (void*)titleData->buffers[2]->data(),
        &err));

    OCL_CHECK(err, cl::Buffer buffer_text_offs(
        context,
        CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY,
        textData->buffers[1]->size(),
        (void*)textData->buffers[1]->data(),
        &err));

    OCL_CHECK(err, cl::Buffer buffer_text_val(
        context,
        CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY,
        textData->buffers[2]->size(),
        (void*)textData->buffers[2]->data(),
        &err));

    OCL_CHECK(err, err = krnl_word_match.setArg(0, buffer_title_offs));
    OCL_CHECK(err, err = krnl_word_match.setArg(1, buffer_title_val));
    OCL_CHECK(err, err = krnl_word_match.setArg(2, buffer_text_offs));
    OCL_CHECK(err, err = krnl_word_match.setArg(3, buffer_text_val));
    OCL_CHECK(err, err = krnl_word_match.setArg(4, first_idx));
    OCL_CHECK(err, err = krnl_word_match.setArg(5, last_idx));

    // Allocate result buffers.
    OCL_CHECK(err, cl::Buffer buffer_res_title_offs(
        context,
        CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,
        4,
        &dummy,
        &err));

    OCL_CHECK(err, cl::Buffer buffer_res_title_val(
        context,
        CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,
        4,
        &dummy,
        &err));

    OCL_CHECK(err, cl::Buffer buffer_res_match(
        context,
        CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,
        4,
        &dummy,
        &err));

    uint64_t res_stats = 0xDEADC0DEDEADC0DEull;

    OCL_CHECK(err, cl::Buffer buffer_res_stats(
        context,
        CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,
        sizeof(res_stats),
        &res_stats,
        &err));

    OCL_CHECK(err, err = krnl_word_match.setArg(6, buffer_res_title_offs));
    OCL_CHECK(err, err = krnl_word_match.setArg(7, buffer_res_title_val));
    OCL_CHECK(err, err = krnl_word_match.setArg(8, buffer_res_match));
    OCL_CHECK(err, err = krnl_word_match.setArg(9, 0 /* TODO_NUM_RESULTS */));
    OCL_CHECK(err, err = krnl_word_match.setArg(10, buffer_res_stats));

    // Configure the search string.
    std::string pattern = "here";
    bool whole_words = false;
    int min_matches = 1;

    uint32_t pattern_data[8];
    char *pattern_chars = reinterpret_cast<char*>(pattern_data);
    int first = 32 - pattern.length();
    if (first < 0) {
        std::cerr << "Search pattern is too long" << std::endl;
        return EXIT_FAILURE;
    }
    for (int i = 0; i < first; i++) {
        pattern_chars[i] = 0;
    }
    for (int i = first; i < 32; i++) {
        pattern_chars[i] = pattern[i - first];
    }
    uint32_t search_config = static_cast<uint32_t>(first);
    if (whole_words) search_config |= 1 << 8;
    search_config |= static_cast<uint32_t>(min_matches) << 16;

    OCL_CHECK(err, err = krnl_word_match.setArg(11, search_config));
    for (int i = 0; i < 8; i++) {
        OCL_CHECK(err, err = krnl_word_match.setArg(12 + i, pattern_data[i]));
    }

    //Copy input data to device global memory
    OCL_CHECK(err, err = q.enqueueMigrateMemObjects(
        {buffer_title_offs, buffer_title_val, buffer_text_offs, buffer_text_val},
        0 /* 0 means from host*/));

    //Launch the Kernel
    OCL_CHECK(err, err = q.enqueueTask(krnl_word_match));

    //Copy Result from Device Global Memory to Host Local Memory
    OCL_CHECK(err, err = q.enqueueMigrateMemObjects(
        {buffer_res_title_offs, buffer_res_title_val, buffer_res_match, buffer_res_stats},
        CL_MIGRATE_MEM_OBJECT_HOST));

    OCL_CHECK(err, err = q.finish());

    //OPENCL HOST CODE AREA END

    // Compare the results of the Device to the simulation
    printf("res_stats: 0x%016llX\n", res_stats);

    return EXIT_SUCCESS;
}

