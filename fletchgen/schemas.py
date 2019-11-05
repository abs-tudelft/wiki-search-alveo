import pyarrow as pa
import subprocess

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

# Run fletchgen
subprocess.run(['fletchgen', '-i', 'pages.as', '-i', 'result.as', '-i', 'stats.as', '-n', 'WordMatch'])
