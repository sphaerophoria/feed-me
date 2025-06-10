#!/usr/bin/env bash

set -ex

jshint
prettier res --check
zig fmt src --check
zig build
zig build test
./integration_test.py
