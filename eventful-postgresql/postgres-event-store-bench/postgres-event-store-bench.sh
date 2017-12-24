#!/usr/bin/env bash

set -eu;

# Benchmark various configurations of postgres as an event store.

export PGHOST=${PGHOST:-localhost}
export PGDATABASE=${PGDATABASE:-postgres_event_store_bench}
export PGUSER=${PGUSER:-postgres}
export PGPASSWORD=${PGPASSWORD:-password}

PSQL="psql --no-psqlrc --quiet"

NUM_CLIENTS=${NUM_CLIENTS:-4}
BENCH_TIME_SECONDS=${BENCH_TIME_SECONDS:-10}
PGBENCH="pgbench --no-vacuum $PGDATABASE --client $NUM_CLIENTS --jobs $NUM_CLIENTS -f pgbench-script.sql --time $BENCH_TIME_SECONDS --report-latencies"

# Spin up a docker container to run postgres tests
if [ ! "$(docker ps -q -f name=postgres_event_store_bench)" ]; then
  if [ "$(docker ps -aq -f name=postgres_event_store_bench)" ]; then
    docker rm postgres_event_store_bench
  fi
  docker run --name postgres_event_store_bench -e "POSTGRES_DB=$PGDATABASE" -p 5432:5432/tcp -d postgres:10 postgres

  # Give time for postgres to start
  sleep 10
fi

recreate_db() {
  local real_pgdatabase="$PGDATABASE"
  PGDATABASE=postgres $PSQL -c "DROP DATABASE IF EXISTS $real_pgdatabase;"
  PGDATABASE=postgres $PSQL -c "CREATE DATABASE $real_pgdatabase;"
}

# Test insertion speed with simple schema and full table lock
recreate_db
$PSQL <<EOF
CREATE TABLE events (
  sequence_number serial PRIMARY KEY,
  event jsonb NOT NULL
);
EOF

cat <<EOF > pgbench-script.sql
BEGIN;
LOCK events IN EXCLUSIVE MODE;
INSERT INTO events (event) VALUES ('{"type":"mytype","value":"hello"}');
COMMIT;
EOF

echo "Full table lock"
$PGBENCH

# Test insertion with trigger as sequence number
recreate_db
$PSQL <<EOF
CREATE TABLE events (
  id serial PRIMARY KEY,
  sequence_number bigint,
  event jsonb NOT NULL,
  UNIQUE (sequence_number)
);

CREATE SEQUENCE events_sequence_number_seq
  START WITH 1
  INCREMENT BY 1
  NO MINVALUE
  NO MAXVALUE
  CACHE 1;

CREATE OR REPLACE FUNCTION update_events_sequence_number()
  RETURNS trigger AS
\$BODY\$
BEGIN
 PERFORM pg_advisory_lock(1);

 UPDATE events
 SET sequence_number = nextval('events_sequence_number_seq'::regclass)
 WHERE id = NEW.id;
 RETURN NEW;
END;
\$BODY\$
LANGUAGE 'plpgsql';

CREATE TRIGGER update_events_sequence_number
AFTER INSERT ON events
FOR EACH ROW
EXECUTE PROCEDURE update_events_sequence_number();
EOF

cat <<EOF > pgbench-script.sql
BEGIN;
INSERT INTO events (event) VALUES ('{"type":"mytype","value":"hello"}');
COMMIT;
EOF

echo "Trigger with advisory lock"
$PGBENCH

# TODO: Test with millions of rows already inserted
# TODO: Insert multiple rows per transaction
# TODO: BRIN indexes
