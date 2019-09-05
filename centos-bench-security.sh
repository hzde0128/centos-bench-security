#!/bin/bash

# rpm -q bugfix
export LANG=en_US.UTF-8

# Simple input to skip slow tests
if [[ "$1" == "--skip-slow" ]]; then
  export BENCH_SKIP_SLOW=1
fi

. includes/log_utils.sh
. includes/test_utils.sh

func_wrapper() {
  local func=$1
  shift
  local args=$@
  ${func} ${args} 
  #2>/dev/null
  if [[ "$?" -eq 127 ]]; then
    warn "${func} not implemented"
  fi
}

main () {  
  yell "# ------------------------------------------------------------------------------
# CentOS Bench for Security 
# 
# Based on 'CIS_CentOS_Linux_7_Benchmark_v2.2.0 (12-27-2017)'
# https://www.cisecurity.org/cis-benchmarks/
#
# Björn Oscarsson (c) 2017-
#
# Inspired by the Docker Bench for Security.
# ------------------------------------------------------------------------------"
  logit "Initializing $(date)"

  ID=$(id -u)
  if [[ "x$ID" != "x0" ]]; then
    logit ""
    warn "Tests requires root to run"
    logit ""
    exit 1
  fi
  
  # Basic tools
  [[ rpm -q net-tools >/dev/null ]] || yum -y -q net-tools

  for test in tests/*.sh
  do
    logit ""
    . ./"$test"
    func_wrapper check_$(echo "$test" | awk -F_ '{print $1}' | cut -d/ -f2)
  done

  logit ""  
}

main "$@"
