import pyarrow as pa
import subprocess
import sys

# Pages schema
pages_title  = pa.field('title', pa.utf8(), nullable=False)
pages_text   = pa.field('text', pa.binary(), nullable=False).add_metadata({b'fletcher_epc': b'8'})
pages_meta   = {b'fletcher_mode': b'read',
                b'fletcher_name': b'Pages'}
pages_schema = pa.schema([pages_title, pages_text]).add_metadata(pages_meta)

pa.output_stream('pages.as').write(pages_schema.serialize());

# Result schema
result_title  = pa.field('title', pa.utf8(), nullable=False)
result_count  = pa.field('count', pa.uint32(), nullable=False)
result_meta   = {b'fletcher_mode': b'write',
                 b'fletcher_name': b'Result'}
result_schema = pa.schema([result_title, result_count]).add_metadata(result_meta)

pa.output_stream('result.as').write(result_schema.serialize());

# Stats schema
stats_schema = pa.schema([pa.field('stats', pa.uint64(), nullable=False)]).add_metadata(
    {b'fletcher_mode': b'write',
     b'fletcher_name': b'Stats'})

pa.output_stream('stats.as').write(stats_schema.serialize());

# If a recordbatch is provided as test case input, trim it and pass it to
# fletchgen instead of the schema.
if len(sys.argv) > 1:
    with open(sys.argv[1], 'rb') as fil:
        tab = pa.RecordBatchFileReader(fil).read_all()
    if len(sys.argv) > 2:
        tab = tab.slice(0, int(sys.argv[2]))
    with open('pages.rb', 'wb') as fil:
        with pa.RecordBatchFileWriter(fil, pages_schema) as writer:
            writer.write_table(tab)
    pages_args = ['-r', 'pages.rb', '-s', 'vhdl/memory.srec']
else:
    pages_args = ['-i', 'pages.as']

# Run fletchgen
subprocess.run(['fletchgen'] + pages_args + ['-i', 'result.as', '-i', 'stats.as', '-n', 'WordMatch', '--sim', '--axi'])
