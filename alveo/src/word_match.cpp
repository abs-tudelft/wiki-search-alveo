
#include "word_match.hpp"
#include <arrow/io/api.h>
#include <arrow/ipc/api.h>

/**
 * Updates the pointers in the C struct to point to the STL containers.
 * Must be called after any of the containers are resized/reallocated.
 */
void WordMatchPartialResultsContainer::synchronize() {
    max_page_title = cpp_max_page_title.c_str();
    num_page_match_records = cpp_page_match_counts.size();
    page_match_counts = cpp_page_match_counts.data();
    page_match_title_offsets = cpp_page_match_title_offsets.data();
    page_match_title_values = cpp_page_match_title_values.c_str();
}

/**
 * Updates the pointers in the C struct to point to the STL containers.
 * Must be called after any of the containers are resized/reallocated.
 */
void WordMatchResultsContainer::synchronize() {
    num_partial_results = cpp_partial_results.size();
    partial_results = cpp_partial_results.data();
}

/**
 * Initializes a dataset loader with the given prefix, loading record
 * batches with filenames of the form `[prefix]-[index].rb`, with `[index]`
 * starting at 0.
 */
WordMatchDatasetLoader::WordMatchDatasetLoader(const std::string &prefix, bool quiet)
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
std::shared_ptr<arrow::RecordBatch> WordMatchDatasetLoader::next() {

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
void WordMatchDatasetLoader::load(std::vector<std::shared_ptr<WordMatch>> impls) {
    for (auto impl : impls) {
        impl->clear_chunks();
    }
    while (auto chunk = next()) {
        for (auto impl : impls) {
            impl->add_chunk(chunk);
        }
    }
}

