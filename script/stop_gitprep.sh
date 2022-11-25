#!/usr/bin/env bash
ps aux | grep gitprep | awk '{print $2}' | xargs kill -INT

