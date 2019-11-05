
#include <string>
#include <vector>
#include <memory>
#include <arrow/api.h>
#include <unistd.h>
#include <arrow/io/api.h>
#include <arrow/ipc/api.h>
#include <omp.h>

std::shared_ptr<arrow::Table> read_input(const std::string &in_prefix) {
    printf("Reading record batches with prefix %s...\n", in_prefix.c_str());
    unsigned int num_batches = 0;
    for (;; num_batches++) {
        std::string fname = in_prefix + "-" + std::to_string(num_batches) + ".rb";
        if (access(fname.c_str(), F_OK) == -1) {
            break;
        }
    }
    std::vector<std::shared_ptr<arrow::RecordBatch>> chunks(num_batches);
    #pragma omp parallel for
    for (unsigned int index = 0; index < num_batches; index++) {
        std::string fname = in_prefix + "-" + std::to_string(index) + ".rb";
        printf("  Read batch %u using thread %d...\n", index, omp_get_thread_num());
        std::shared_ptr<arrow::io::MemoryMappedFile> file;
        arrow::Status status = arrow::io::MemoryMappedFile::Open(fname, arrow::io::FileMode::type::READ, &file);
        if (!status.ok()) {
            throw std::runtime_error("MemoryMappedFile::Open failed for " + fname + ": " + status.ToString());
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
        chunks[index] = batch;
    }
    std::shared_ptr<arrow::Table> table;
    arrow::Status status = arrow::Table::FromRecordBatches(chunks, &table);
    if (!status.ok()) {
        throw std::runtime_error("Table::FromRecordBatches failed: " + status.ToString());
    }
    printf("Read %lld rows into memory.\n", (long long)table->num_rows());
    return table;
}

void write_output(std::shared_ptr<arrow::Table> table, const std::string &out_prefix, const unsigned int num_chunks) {
    auto title_chunks = table->column(0);
    auto data_chunks = table->column(1);

    int64_t data_size = 0;
    for (int ci = 0; ci < title_chunks->num_chunks(); ci++) {
        auto datas = std::dynamic_pointer_cast<arrow::BinaryArray, arrow::Array>(data_chunks->chunk(ci));
        data_size += datas->value_offset(datas->length());
    }

    printf("Compressed data size read: %lld bytes.\n", (long long)data_size);

    unsigned int current_chunk = 0;
    int64_t data_count = 0;
    arrow::Status status;

    std::unique_ptr<arrow::RecordBatchBuilder> builder;
    status = arrow::RecordBatchBuilder::Make(table->schema(), arrow::default_memory_pool(), &builder);
    if (!status.ok()) {
        throw std::runtime_error("RecordBatchBuilder::Make failed: " + status.ToString());
    }

    for (int ci = 0; ci < title_chunks->num_chunks(); ci++) {
        auto titles = std::dynamic_pointer_cast<arrow::StringArray, arrow::Array>(title_chunks->chunk(ci));
        auto datas = std::dynamic_pointer_cast<arrow::BinaryArray, arrow::Array>(data_chunks->chunk(ci));
        for (int64_t ri = 0; ri < datas->length(); ri++) {
            std::string title = titles->GetString(ri);
            status = builder->GetFieldAs<arrow::BinaryBuilder>(0)->Append(title);
            if (!status.ok()) {
                throw std::runtime_error("BinaryBuilder::Append failed (title): " + status.ToString());
            }
            std::string data = datas->GetString(ri);
            status = builder->GetFieldAs<arrow::BinaryBuilder>(1)->Append(data);
            if (!status.ok()) {
                throw std::runtime_error("BinaryBuilder::Append failed (data): " + status.ToString());
            }
            data_count += data.size();

            if (data_count >= (data_size * (current_chunk + 1)) / num_chunks) {
                printf("  Flush batch %u...\n", current_chunk);
                std::shared_ptr<arrow::RecordBatch> batch;
                status = builder->Flush(&batch);
                if (!status.ok()) {
                    throw std::runtime_error("RecordBatchBuilder::Flush failed (data):" + status.ToString());
                }
                printf("  Write batch %u...\n", current_chunk);
                {
                    std::string fname = out_prefix + "-" + std::to_string(current_chunk) + ".rb";
                    std::shared_ptr<arrow::io::OutputStream> file;
                    arrow::Status status = arrow::io::FileOutputStream::Open(fname, &file);
                    if (!status.ok()) {
                        throw std::runtime_error("FileOutputStream::Open failed for " + fname + ": " + status.ToString());
                    }
                    std::shared_ptr<arrow::ipc::RecordBatchWriter> writer;
                    status = arrow::ipc::RecordBatchFileWriter::Open(file.get(), table->schema(), &writer);
                    if (!status.ok()) {
                        throw std::runtime_error("RecordBatchFileWriter::Open failed for " + fname + ": " + status.ToString());
                    }
                    status = writer->WriteRecordBatch(*batch);
                    if (!status.ok()) {
                        throw std::runtime_error("RecordBatchFileWriter::WriteRecordBatch failed for " + fname + ": " + status.ToString());
                    }
                    writer->Close();
                }
                printf("  Finished writing batch %u\n", current_chunk);

                current_chunk += 1;
            }
        }
    }

    printf("Compressed data size written: %lld bytes.\n", (long long)data_count);
    if (data_count != data_size || current_chunk != num_chunks) {
        throw std::runtime_error("checksum failure");
    }

}

int main(int argc, char *argv[]) {

    // Parse command line.
    if (argc < 3) {
        printf("Usage: %s <input-prefix> <output-prefix> [number-of-chunks=15]\n", argv[0]);
        exit(1);
    }
    std::string input_prefix  = argv[1];
    std::string output_prefix = (argc > 2) ? argv[2] : "xclbin/word_match";
    int num_chunks = (argc > 3) ? atoi(argv[3]) : 0;
    if (num_chunks < 1) {
        num_chunks = 15;
    }

    // Execute the command.
    write_output(read_input(input_prefix), output_prefix, num_chunks);

}
