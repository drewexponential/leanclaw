#!/bin/sh
set -e

exec node dist/index.js gateway --allow-unconfigured --port 3000 --bind lan
