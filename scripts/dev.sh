#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-help}" in
  setup)
    flutter pub get
    ;;
  run)
    (cd de && flutter run -d linux "${@:2}")
    ;;
  analyze)
    flutter pub get
    flutter analyze
    ;;
  test)
    flutter pub get
    flutter test --coverage
    ;;
  goldens)
    flutter pub get
    flutter test test/goldens_test.dart --update-goldens
    ;;
  *)
    echo "usage: dev.sh {setup|run|analyze|test|goldens}" >&2
    exit 1
    ;;
esac
