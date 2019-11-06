Data preparation
================

Description
-----------

This folder contains the Scala/Apache Spark code that converts Wikipedia
database dumps to Arrow IPC record batch files for further processing by the
optimization tool or the demo directly.

Dependencies
------------

 - Java 8.
 - Scala build tool (`sbt`).
 - Apache Spark 2.4.4.

Usage
-----

First, you'll need to download a Wikipedia database dump to convert. You can
get these from [dumps.wikimedia.org](https://dumps.wikimedia.org/). The file
you'll want will be named `<language>-<version>-pages-articles-multistream.xml.bz2`.
For instance, [this](https://dumps.wikimedia.org/simplewiki/latest/simplewiki-latest-pages-articles-multistream.xml.bz2)
is the file for the latest simple English Wikipedia; simple English is good for
testing because it's much smaller than the regular English Wikipedia.

Once you have the file, run `sbt package` to build the JAR. Then you can use
Spark to start the job as follows:

```
spark-submit \
    --packages com.databricks:spark-xml_2.11:0.6.0 \
    target/scala-2.11/wikipedia-to-arrow-with-snappy_2.11-1.0.jar \
    <wikipedia-dump.xml.bz2> <output-prefix>
```

This will write a number of record batch files, named
`<output-prefix>-<index>.rb`, where `<index>` ranges from 0 to the number of
partitions (determined by Spark) minus one. This is exactly the format expected
by the other tools.

For optimal performance, you can use the optimization tool in the `optimize`
folder to repartition the dataset to an integer multiple of the number of
hardware kernels.
