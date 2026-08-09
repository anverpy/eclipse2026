# Glue Catalog: single "events" table over the unified envelope (see README),
# partitioned by source/dt/hour matching the S3 key layout written by s3_writer.py.
#
# No Crawler: schema is fixed and known (envelope.py), and partition discovery
# uses partition projection instead of crawler/MSCK REPAIR — zero standing
# infra, zero crawler run cost, no drift between table and actual keys.
# `raw` is typed STRING (not STRUCT) because its shape differs per source;
# OpenX JsonSerDe auto-serializes the nested JSON object into that string
# column, query it with json_extract() in Athena.

resource "aws_glue_catalog_database" "eclipse2026" {
  name = "${var.project}_db"
}

resource "aws_glue_catalog_table" "events" {
  name          = "events"
  database_name = aws_glue_catalog_database.eclipse2026.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification = "json"

    "projection.enabled" = "true"

    "projection.source.type"   = "enum"
    "projection.source.values" = "ree,aemet,dgt_traffic,trends,dgt_camera"

    "projection.dt.type"   = "date"
    "projection.dt.range"  = "2026-08-07,2026-08-13"
    "projection.dt.format" = "yyyy-MM-dd"

    "projection.hour.type"   = "integer"
    "projection.hour.range"  = "0,23"
    "projection.hour.digits" = "2"

    "storage.location.template" = "s3://${local.data_lake_bucket}/source=$${source}/dt=$${dt}/hour=$${hour}/"
  }

  storage_descriptor {
    location      = "s3://${local.data_lake_bucket}/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "ts_utc"
      type = "string"
    }
    columns {
      name = "station_or_camera_id"
      type = "string"
    }
    columns {
      name = "lat"
      type = "double"
    }
    columns {
      name = "lon"
      type = "double"
    }
    columns {
      name = "metric_name"
      type = "string"
    }
    columns {
      name = "value"
      type = "double"
    }
    columns {
      name = "unit"
      type = "string"
    }
    columns {
      name = "raw"
      type = "string"
    }
  }

  partition_keys {
    name = "source"
    type = "string"
  }
  partition_keys {
    name = "dt"
    type = "string"
  }
  partition_keys {
    name = "hour"
    type = "string"
  }
}
