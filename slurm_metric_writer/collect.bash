#!/bin/bash

# URL of influxDB
export db_endpoint="http://1.2.3.4:8086"
# database to push the data in
export database="metrics"
# HTTP basic auth user
export username="telegraf"
# HTTP basic auth password
export password="telegraf"
# slurm timeout
export slurm_timeout=5
# curl timeout
curl_timeout=5


SINFO="/usr/bin/sinfo"
SCONTROL="/usr/bin/scontrol"
SQUEUE="/usr/bin/squeue"


DEBUG=1

function echo_debug () {
  message="$1"
  if [ -n "$DEBUG" ]; then
    echo "${message}"
  fi
}

curl_prefix_template="timeout ${curl_timeout} curl --silent --show-error --include -u $username:$password -XPOST \"$db_endpoint/write?db=$database&precision=s\" --data-binary"


# ****************************
metric='slurm.partition_usage'
# ****************************

# we parse output of command:
# $ sinfo -O partitionname,nodeaiot
# PARTITION           NODES(A/I/O/T)    # that means "allocated/idle/other/total"
# long                22/5/0/27
# gpu                 0/0/1/1
# short               22/5/1/28
# debug               2/1/1/4
# $

sinfo_data=$(timeout ${slurm_timeout} ${SINFO} -O partitionname:40,nodeaiot)	# call sinfo and collect data
partition_list=$(echo "$sinfo_data" | awk '{print $1}' | tail -n +2 | xargs)	# extract partition list
seconds=$(date +%s) #current unix time


for partition in ${partition_list}; do
  partition_data=$(echo "$sinfo_data" | grep $partition | xargs)
  echo_debug "partition_data: ${partition_data}"
  # format is like allocated/idle/other/total
  #
  # long 21/4/0/25
  # gpu 0/1/0/1
  # short 17/6/0/23
  # debug 0/3/0/3

  cnt_allocated=$(echo "$partition_data" | cut -d ' ' -f 2 | cut -d '/' -f 1 | xargs)
  cnt_idle=$(echo "$partition_data" | cut -d '/' -f 2 | xargs)
  cnt_other=$(echo "$partition_data" | cut -d '/' -f 3 | xargs)
  cnt_total=$(echo "$partition_data" | cut -d '/' -f 4 | xargs)

  cmd_string="${curl_prefix_template} \"${metric},partition=${partition} cnt_allocated=${cnt_allocated},cnt_idle=${cnt_idle},cnt_other=${cnt_other},cnt_total=${cnt_total} $seconds\""
  echo_debug "cmd: ${cmd_string}"
  res=$(eval $cmd_string)
  rc=$?
  echo_debug "rc: ${rc}, res: ${res}"

done

#curl options used:
# -S, --show-error .. When used with -s it makes curl show an error message if it fails.
# -s, --silent .. Silent or quiet mode. Don't show progress meter or error messages.  Makes Curl mute.
# -i, --include .. (HTTP) Include the HTTP-header in the output. The HTTP-header includes things like server-name, date of the document, HTTP-version and more...


# ************************
metric='slurm.queue_stats'
# ************************


# * running jobs ("R" state in slurm)
seconds=$(date +%s)
running_jobs=$(timeout ${slurm_timeout} ${SQUEUE} -t R --noheader | wc -l)
echo_debug "running_jobs: ${running_jobs}"
cmd_string="${curl_prefix_template} \"${metric},metric=running value=${running_jobs} $seconds\""
res=$(eval $cmd_string)
rc=$?

# * waiting jobs ("PD" state in slurm)
seconds=$(date +%s)
waiting_jobs=$(timeout ${slurm_timeout} ${SQUEUE} -t PD --noheader | wc -l)
echo_debug "waiting_jobs: ${waiting_jobs}"
cmd_string="${curl_prefix_template} \"${metric},metric=waiting value=${waiting_jobs} $seconds\""
res=$(eval $cmd_string)
rc=$?


# **************************
metric='slurm.node_stats'
# **************************

seconds=$(date +%s)
drained_nodes=$(timeout ${slurm_timeout} ${SINFO} -R --noheader| wc -l)
echo_debug "drained_nodes: ${drained_nodes}"
cmd_string="${curl_prefix_template} \"${metric},metric=drained value=${drained_nodes} $seconds\""
res=$(eval $cmd_string)
rc=$?

# **************************
metric='slurm.node_status'
# **************************

seconds=$(date +%s)
nodelist=$(${SCONTROL} show nodes -o | awk '{print $1}' | cut -d '=' -f 2 | xargs)

for node in ${nodelist}; do

  state=$(${SCONTROL} show -o node=${node} | tr ' ' '\n' | grep State | cut -d '=' -f 2)
  echo_debug "node: ${node} / state: ${state}"

  #combined states conversion:

  if [[ "$state" == *"POWER"* ]]; then state="POWER"; fi
  if [[ "$state" == "MIXED+DRAIN" ]]; then state="MIXED"; fi
  if [[ "$state" == "ALLOCATED+DRAIN" ]]; then state="ALLOCATED"; fi
  if [[ "$state" == "IDLE+DRAIN" ]]; then state="DRAIN"; fi

  possible_states="ALLOCATED IDLE MIXED RESERVED POWER DRAIN"
  for state_test in ${possible_states}; do
    if [[ "$state" == "$state_test" ]]; then
      cmd_string="${curl_prefix_template} \"${metric},metric=$state_test,node=$node value=1 $seconds\""
      res=$(eval $cmd_string)
      rc=$?
      echo_debug "curl_rc: $rc, state: ${state_test}, node: ${node}, value: 1"
    else
      cmd_string="${curl_prefix_template} \"${metric},metric=$state_test,node=$node value=0 $seconds\""
      res=$(eval $cmd_string)
      rc=$?
      echo_debug "curl_rc: $rc, state: ${state_test}, node: ${node}, value: 0"
    fi
  done
done

