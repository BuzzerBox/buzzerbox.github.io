#!/bin/sh
# Preview the site on http://localhost:4000 with Docker (no local Ruby needed).
# Syncs the docs from ../BuzzerBox first (override with BUZZERBOX_DIR).
set -e
cd "$(dirname "$0")/.."
docker run --rm -v "$PWD":/site -v "${BUZZERBOX_DIR:-$PWD/../BuzzerBox}":/src/BuzzerBox:ro \
  -v buzzerbox-site-gems:/usr/local/bundle -w /site -p 4000:4000 ruby:3.3 \
  sh -c 'bundle install --quiet && ruby scripts/sync-docs.rb /src/BuzzerBox &&
         bundle exec jekyll serve --host 0.0.0.0 --livereload --force_polling'
