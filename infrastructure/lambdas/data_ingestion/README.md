# Data Ingestion Lambda

This function accepts market listing JSON and inserts it into PostgreSQL.

`psycopg2-binary` is packaged as a Lambda layer from `layer/python`.

To rebuild the layer contents:

```sh
python3 -m pip install \
  --platform manylinux2014_x86_64 \
  --implementation cp \
  --python-version 3.12 \
  --only-binary=:all: \
  --target infrastructure/lambdas/data_ingestion/layer/python \
  -r infrastructure/lambdas/data_ingestion/requirements.txt \
  --upgrade
```
