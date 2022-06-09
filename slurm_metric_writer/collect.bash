#!/bin/bash

# URL of influxDB
export db_endpoint="http://172.16.120.1:8086"
# database to push the data in
export database="metrics"
# HTTP basic auth user
export username="telegraf"
# HTTP basic auth password
export password="NotRealPassword"
# slurm timeout
export slurm_timeout=5
# curl timeout
curl_timeout=5

SINFO="/usr/bin/sinfo"
SCONTROL="/usr/bin/scontrol"
SQUEUE="/usr/bin/squeue"
SDIAG="/usr/bin/sdiag"


#DEBUG=1

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

# $ sinfo -O partitionname,nodeaiot
# PARTITION           NODES(A/I/O/T)    # that means "allocated/idle/other/total"
# part1               22/5/0/27
# part2               0/0/1/1

sinfo_data=$(timeout ${slurm_timeout} ${SINFO} -O partitionname:40,nodeaiot)    # call sinfo and collect data
partition_list=$(echo "$sinfo_data" | awk '{print $1}' | tail -n +2 | xargs)    # extract partition list
seconds=$(date +%s) #current unix time


for partition in ${partition_list}; do
  partition_data=$(echo "$sinfo_data" | grep $partition | xargs)
  echo_debug "partition_data: ${partition_data}"

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

sdiag_output=$(timeout ${slurm_timeout} ${SDIAG} 2>&1 )

sdiag_job_states_ts=$(echo "${sdiag_output}" | grep 'Job states ts' | cut -d '(' -f 2 | tr -d ')' | xargs)
sdiag_jobs_pending=$(echo "${sdiag_output}" | grep 'Jobs pending' | cut -d ':' -f 2 | xargs)
sdiag_jobs_running=$(echo "${sdiag_output}" | grep 'Jobs running' | cut -d ':' -f 2 | xargs)

echo_debug "sdiag ts: ${sdiag_job_states_ts} sdiag jobs pending: ${sdiag_jobs_pending} sdiag jobs running: ${sdiag_jobs_running}"

#submit it to influx (check if vars are numbers really
[[ $sdiag_jobs_running == ?(-)+([0-9]) ]] && cmd_string="${curl_prefix_template} \"${metric},metric=running value=${sdiag_jobs_running} ${sdiag_job_states_ts}\"" && res=$(eval $cmd_string)
[[ $sdiag_jobs_pending == ?(-)+([0-9]) ]] && cmd_string="${curl_prefix_template} \"${metric},metric=waiting value=${sdiag_jobs_pending} ${sdiag_job_states_ts}\"" && res=$(eval $cmd_string)


# **************************
metric='slurm.node_status'
# **************************

nodes_mixed=0
nodes_allocated=0
nodes_drained=0
nodes_power=0

#seconds=$(date +%s)
nodelist=$(${SCONTROL} show nodes -o | awk '{print $1}' | cut -d '=' -f 2 | xargs)

for node in ${nodelist}; do

  seconds=$(date +%s)
  state=$(${SCONTROL} show -o node=${node} | tr ' ' '\n' | grep State | cut -d '=' -f 2)
  echo_debug "node: ${node} / state: ${state}"

  #combined states conversion:

  if [[ "$state" == *"POWER"* ]]; then state="POWER"; fi
  if [[ "$state" == "MIXED+DRAIN" ]]; then state="MIXED"; fi
  if [[ "$state" == "ALLOCATED+DRAIN" ]]; then state="ALLOCATED"; fi
  if [[ "$state" == "IDLE+DRAIN" ]]; then state="DRAIN"; fi
  if [[ "$state" == "DOWN+DRAIN" ]]; then state="DRAIN"; fi

  case ${state} in
    MIXED)
      statevar=1
      nodes_mixed=$((nodes_mixed+1))
      ;;
    ALLOCATED)
      statevar=2
      nodes_allocated=$((nodes_allocated+1))
      ;;
    IDLE)
      statevar=4
      nodes_idle=$((nodes_idle+1))
      ;;
    DRAIN)
      statevar=8
      nodes_drained=$((nodes_drained+1))
      ;;
    POWER)
      statevar=16
      nodes_power=$((nodes_power+1))
      ;;
    *)
      statevar=0
      ;;
   esac

   cmd_string="${curl_prefix_template} \"${metric},node=$node state=${statevar} $seconds\""
   res=$(eval $cmd_string)

done

# **************************
metric='slurm.node_stats'
# **************************


seconds=$(date +%s)
data="drained=${nodes_drained},allocated=${nodes_allocated},mixed=${nodes_mixed},power=${nodes_power}"
echo_debug "${metric}: ${data}"
cmd_string="${curl_prefix_template} \"${metric} ${data} $seconds\""
res=$(eval $cmd_string)
rc=$?
#echo_debug "rc: ${rc}, res: ${res}"
