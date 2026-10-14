#!/bin/bash
# usage: build.sh <tree-dir> <driver.ml basename> <out-name>
cd "$1/arm" || exit 2
exec nice -n 10 ../tools/build-proof.sh "../../tests/$2" /home/bluestar/twins-lanes/s2n-dup-20261014/hol-light/hol.sh "../../runs/$3.native"
