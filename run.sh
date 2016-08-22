#!/bin/bash
set -e

./gitprep

tail -f log/production.log
