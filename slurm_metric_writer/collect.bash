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



DEBUG=1




function curl_wrapper_1 () {
  value=$1
  tag_partition=$2
  tag_metric=$3
  metric=$4
  
  timeout ${curl_timeout} curl -i -u $username:$password -XPOST "$db_endpoint/write?db=$database&precision=s" --data-binary "${metric},partition=${partition},metric=${tag_metric} value=${value} $seconds" &> /dev/null

  if [ -n "$DEBUG" ]; then
    echo "xpost: $db_endpoint/write?db=$database&precision=s"
    echo "data-binary: ${metric},partition=${partition},metric=${tag_metric} value=${value} $seconds"
  fi

}



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

sinfo_data=$(timeout ${slurm_timeout} sinfo -O partitionname,nodeaiot)	# call sinfo and collect data

export seconds=$(date +%s) #current unix time

partition_list=$(echo "$sinfo_data" | awk '{print $1}' | tail -n +2 | xargs)	# extract partition list

for partition in ${partition_list}; do
  partition_data=$(echo "$sinfo_data" | grep $partition | xargs)

  value=$(echo "$partition_data" | cut -d ' ' -f 2 | cut -d '/' -f 1 | xargs) && curl_wrapper_1 ${value} $partition 'allocated' $metric
  value=$(echo "$partition_data" | cut -d '/' -f 2 | xargs) && curl_wrapper_1 ${value} $partition 'idle' $metric
  value=$(echo "$partition_data" | cut -d '/' -f 3 | xargs) && curl_wrapper_1 ${value} $partition 'other' $metric
  value=$(echo "$partition_data" | cut -d '/' -f 4 | xargs) && curl_wrapper_1 ${value} $partition 'total' $metric

done

# ************************
metric='slurm.queue_stats'
# ************************

seconds=$(date +%s) #just for case of significant before

running_jobs=$(timeout ${slurm_timeout} squeue -t R --noheader | wc -l) && seconds=$(date +%s) \
  && timeout ${curl_timeout} curl -i -u $username:$password -XPOST "$db_endpoint/write?db=$database&precision=s" --data-binary "${metric},metric=running value=${running_jobs} $seconds" &> /dev/null
waiting_jobs=$(timeout ${slurm_timeout} squeue -t PD --noheader | wc -l) && seconds=$(date +%s) \
  && timeout ${curl_timeout} curl -i -u $username:$password -XPOST "$db_endpoint/write?db=$database&precision=s" --data-binary "${metric},metric=waiting value=${waiting_jobs} $seconds" &> /dev/null

# **************************
metric='slurm.node_stats'
# **************************

seconds=$(date +%s) #just for case of significant before

drained_nodes=$(timeout ${slurm_timeout} sinfo -R --noheader| wc -l) \
  && timeout ${curl_timeout} curl -i -u $username:$password -XPOST "$db_endpoint/write?db=$database&precision=s" --data-binary "${metric},metric=drained value=${drained_nodes} $seconds" &> /dev/null

# **************************
metric='slurm.node_status'
# **************************

scontrol_o_raw=$(scontrol show nodes -o)
nodelist=$(echo "$scontrol_o_raw" | awk '{print $1}' | cut -d '=' -f 2 | xargs)

for node in ${nodelist}; do

  state=$(echo "$scontrol_o_raw" | grep "$node " | sed -n -e 's/^.*State=//p' | cut -d ' ' -f 1)

  #combined states conversion:
  if [[ "$state" == "MIXED+DRAIN" ]]; then
    state="MIXED"
  fi

  if [[ "$state" == "ALLOCATED+DRAIN" ]]; then
    state="ALLOCATED"
  fi

  possible_states="ALLOCATED IDLE MIXED RESERVED"
  for state_test in ${possible_states}; do
    if [[ "$state" == "$state_test" ]]; then
      timeout ${curl_timeout} curl -i -u $username:$password -XPOST "$db_endpoint/write?db=$database&precision=s" --data-binary "${metric},metric=$state_test,node=$node value=1 $seconds" &> /dev/null
    else
      timeout ${curl_timeout} curl -i -u $username:$password -XPOST "$db_endpoint/write?db=$database&precision=s" --data-binary "${metric},metric=$state_test,node=$node value=0 $seconds" &> /dev/null
    fi
  done
done

