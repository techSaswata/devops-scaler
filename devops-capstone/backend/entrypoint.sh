#!/bin/sh
# Run migrations, then hand over to the real command.
#
# RUN_MIGRATIONS exists so this is a choice rather than a default. In compose it
# is convenient; in Kubernetes it is wrong, because N replicas would all race to
# migrate the same database on every rollout. There the Helm chart runs Alembic
# once in a pre-upgrade Job and sets RUN_MIGRATIONS=false here.
set -e
if [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
  echo "[entrypoint] applying database migrations"
  alembic upgrade head
fi
exec "$@"
