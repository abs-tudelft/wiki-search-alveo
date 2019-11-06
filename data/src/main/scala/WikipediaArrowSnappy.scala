import org.xerial.snappy.Snappy

import collection.JavaConverters._
import java.io._

import org.apache.log4j.Logger
import org.apache.log4j.Level

import org.apache.arrow.memory._
import org.apache.arrow.vector._
import org.apache.arrow.vector.ipc._
import org.apache.arrow.vector.types.pojo._
import org.apache.arrow.vector.util._

import org.apache.spark.sql._
import org.apache.spark.sql.catalyst.InternalRow
import org.apache.spark.sql.execution.arrow._
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._
import org.apache.spark.TaskContext
import org.apache.spark.unsafe.types.UTF8String

import com.databricks.spark.xml._

object WikipediaArrowSnappy {
  def main(args: Array[String]) {

    // input xml
    val input = args(0)

    // output filename
    val output = args(1)

    val spark = SparkSession.builder
      .appName("Wikipedia to Arrow with Snappy")
      .config("arrow.memory.debug.allocator", true)
      .getOrCreate

    import spark.implicits._

    // Logger.getLogger("org").setLevel(Level.DEBUG)

    val wikiSchema = StructType(
      Array(
        StructField("id", LongType),
        StructField("ns", LongType),
        StructField(
          "redirect",
          StructType(
            Array(
              StructField("_VALUE", StringType),
              StructField("_title", StringType)
            )
          )
        ),
        StructField("reStringTypections", StringType),
        StructField(
          "revision",
          StructType(
            Array(
              StructField(
                "comment",
                StructType(
                  Array(
                    StructField("_VALUE", StringType),
                    StructField("_deleted", StringType)
                  )
                )
              ),
              StructField(
                "contributor",
                StructType(
                  Array(
                    StructField("_VALUE", StringType),
                    StructField("_deleted", StringType),
                    StructField("id", LongType),
                    StructField("ip", StringType),
                    StructField("username", StringType)
                  )
                )
              ),
              StructField("format", StringType),
              StructField("id", LongType),
              StructField("minor", StringType),
              StructField("model", StringType),
              StructField("parentid", LongType),
              StructField("sha1", StringType),
              StructField(
                "text",
                StructType(
                  Array(
                    StructField("_VALUE", StringType),
                    StructField("_space", StringType)
                  )
                )
              ),
              StructField("timestamp", StringType)
            )
          )
        ),
        StructField("title", StringType)
      )
    )

    val replace = raw"\[\[(?:[^\]\[]+\|)?([^\]\[]+)\]\]"

    // Create Snappy compress UDF
    val compress: String => Array[Byte] = x =>
      Snappy.compress(x.getBytes("UTF-8"))
    val snappy = udf(compress)

    spark.read
      .schema(wikiSchema)
      .option("rowTag", "page")
      .option("mode", "DROPMALFORMED")
      .xml(input)
      .select($"title", $"revision.text._VALUE".as("text"))
      .na
      .drop
      .filter(not($"title".rlike("[A-Za-z_0-9]+:[^ ].*")))
      .select(
        $"title",
        snappy(
          regexp_replace(
            regexp_replace($"text", replace, "$1"),
            replace,
            "$1"
          )
        )
      )
      .foreachPartition { partition =>
        {
          val titleField = new FieldType(false, new ArrowType.Utf8(), null)
          val textField = new FieldType(
            false,
            new ArrowType.Binary(),
            null,
            Map("fletcher_epc" -> "8").asJava
          )
          val arrowSchema = new Schema(
            Iterable(
              new Field("title", titleField, null),
              new Field("text", textField, null)
            ).asJava,
            Map(
              "fletcher_mode" -> "read",
              "fletcher_name" -> "Pages"
            ).asJava
          )
          val root = VectorSchemaRoot.create(arrowSchema, ArrowUtils.rootAllocator)
          val writer = execution.arrow.ArrowWriter.create(root)
          partition.foreach { row =>
            {
              writer.write(
                InternalRow.fromSeq(
                  row.toSeq.updated(0, UTF8String.fromString(row.getString(0)))
                )
              )
            }
          }
          writer.finish

          val outputStream = new FileOutputStream(
            output + "-" + TaskContext.getPartitionId + ".rb"
          )
          val fileWriter =
            new ArrowFileWriter(root, null, outputStream.getChannel())
          fileWriter.start
          fileWriter.writeBatch
          fileWriter.end

          root.close
        }
      }

    spark.stop

  }
}
