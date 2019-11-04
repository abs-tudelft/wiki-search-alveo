
#include "software.hpp"
#include <snappy.h>
#include <omp.h>
#include <chrono>
#include <string.h>
#include <ctype.h>

/**
 * Constructs the software word matcher.
 */
SoftwareWordMatch::SoftwareWordMatch() {
}

/**
 * Resets the dataset stored in device memory.
 */
void SoftwareWordMatch::clear_chunks() {
    chunks.clear();
}

/**
 * Adds the given chunk to the dataset stored in device memory.
 */
void SoftwareWordMatch::add_chunk(const std::shared_ptr<arrow::RecordBatch> &batch) {
    chunks.push_back(batch);
}

/**
 * Runs the kernel with the given configuration.
 */
void SoftwareWordMatch::execute(const WordMatchConfig &config,
    void (*progress)(void *user, const char *status), void *progress_user
) {

    // Get a Table representation of the data.
    std::shared_ptr<arrow::Table> table;
    arrow::Status status = arrow::Table::FromRecordBatches(chunks, &table);
    if (!status.ok()) {
        throw std::runtime_error("Table::FromRecordBatches failed: " + status.ToString());
    }

    // Make sure we have enough presults result records and clear them.
    results.cpp_partial_results.resize(omp_get_max_threads());
    for (auto &presults : results.cpp_partial_results) {
        presults.num_word_matches = 0;
        presults.num_page_matches = 0;
        presults.cpp_page_match_counts.clear();
        presults.cpp_page_match_title_offsets.clear();
        presults.cpp_page_match_title_values.clear();
        presults.cpp_page_match_title_offsets.push_back(0);
        presults.max_word_matches = 0;
        presults.cpp_max_page_title.clear();
        presults.cycle_count = 0;
        presults.clock_frequency = 0;
        presults.data_size = 0;
        presults.time_taken = 0;
    }

    // Start measuring execution time.
    auto start = std::chrono::high_resolution_clock::now();
    if (progress) {
        std::string msg = "Running on CPU...";
        progress(progress_user, msg.c_str());
    }

    #pragma omp parallel
    {
        // Determine what our slice of the table and result record is.
        int tcnt = omp_get_num_threads();
        int tid = omp_get_thread_num();
        auto &presults = results.cpp_partial_results[tid];
        int64_t stai = (table->num_rows() * tid) / tcnt;
        int64_t stoi = (table->num_rows() * (tid + 1)) / tcnt;
        auto slice = table->Slice(stai, stoi - stai);
        auto title_chunks = slice->column(0);
        auto data_chunks = slice->column(1);

        // Data buffer for the uncompressed article text.
        std::string article_text;

        // Iterate over the chunks in our slice of the table.
        if (title_chunks->num_chunks() != data_chunks->num_chunks()) {
            throw std::runtime_error("unexpected chunking");
        }
        for (int ci = 0; ci < title_chunks->num_chunks(); ci++) {
            auto titles = std::dynamic_pointer_cast<arrow::StringArray, arrow::Array>(title_chunks->chunk(ci));
            auto data = std::dynamic_pointer_cast<arrow::BinaryArray, arrow::Array>(data_chunks->chunk(ci));
            if (titles->length() != data->length()) {
                throw std::runtime_error("unexpected chunking");
            }
            unsigned int max_page_cnt = 0;
            unsigned int max_page_idx = 0;
            for (unsigned int ii = 0; ii < titles->length(); ii++) {

                // Get the article data pointer and size from Arrow.
                int32_t article_data_size;
                const char *article_data_ptr = (const char*)data->GetValue(ii, &article_data_size);
                presults.data_size += article_data_size + 4;

                // Perform Snappy decompression.
                size_t uncompressed_length;
                if (!snappy::GetUncompressedLength(article_data_ptr, article_data_size, &uncompressed_length)) {
                    throw std::runtime_error("snappy decompression error");
                }
                article_text.resize(uncompressed_length);
                if (!snappy::RawUncompress(article_data_ptr, article_data_size, &article_text[0])) {
                    throw std::runtime_error("snappy decompression error");
                }

                // Perform matching.
                unsigned int num_matches = 0;
                const char *ptr = article_text.c_str();
                const char *end = ptr + strlen(ptr);
                if (config.whole_words) {
                    int patsize = config.pattern.size();
                    bool first = true;
                    ptr--;
                    for (; ptr < end - patsize; ptr++, first = false) {
                        if (strncmp(ptr+1, config.pattern.c_str(), patsize)) {
                            continue;
                        }
                        if (!first && (isalnum(*ptr) || *ptr == '_')) {
                            continue;
                        }
                        if (ptr+1+patsize < end && (isalnum(*(ptr+1+patsize)) || *(ptr+1+patsize) == '_')) {
                            continue;
                        }
                        num_matches++;
                    }
                } else {
                    while (ptr < end) {
                        ptr = strstr(ptr, config.pattern.c_str());
                        if (ptr) {
                            ptr++;
                            num_matches++;
                        } else {
                            break;
                        }
                    }
                }

                presults.num_word_matches += num_matches;
                if (num_matches >= config.min_matches) {
                    presults.num_page_matches++;
                    if (presults.cpp_page_match_counts.size() < 256) {
                        presults.cpp_page_match_counts.push_back(num_matches);
                        presults.cpp_page_match_title_values += titles->GetString(ii);
                        presults.cpp_page_match_title_offsets.push_back(
                            presults.cpp_page_match_title_values.size());
                    }
                }
                if (num_matches >= max_page_cnt) {
                    max_page_cnt = num_matches;
                    max_page_idx = ii;
                }
            }

            // Load the title of the page with the most matches.
            if (max_page_cnt >= presults.max_word_matches) {
                presults.max_word_matches = max_page_cnt;
                presults.cpp_max_page_title = titles->GetString(max_page_idx);
            }
        }
    }

    // Finish measuring execution time.
    auto elapsed = std::chrono::high_resolution_clock::now() - start;
    results.time_taken = std::chrono::duration_cast<std::chrono::microseconds>(elapsed).count();
    if (progress) {
        std::string msg = "Running on CPU... done";
        progress(progress_user, msg.c_str());
    }

    // Synchronize all the results.
    for (auto &presults : results.cpp_partial_results) {
        presults.synchronize();
    }
    results.synchronize();

}
