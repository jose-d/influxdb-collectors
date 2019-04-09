#!/bin/bash

# URL of influxDB
db_endpoint="http://172.16.120.1:8086"
# database to push the data in
database="metrics"
# HTTP basic auth user
username=""
# HTTP basic auth password
password=""
# slurm timeout
slurm_timeout=5
# curl timeout
curl_timeout=5



# ****************************
metric='slurm.partition_usage'
# ****************************

# we parse output of command:
# jose@koios1:~$ sinfo -O partitionname,nodeaiot
# PARTITION           NODES(A/I/O/T)	# that means "allocated/idle/other/total"
# long                22/5/0/27
# gpu                 0/0/1/1
# short               22/5/1/28
# debug               2/1/1/4
# jose@koios1:~$

sinfo_data=$(timeout ${slurm_timeout} sinfo -O partitionname,nodeaiot)	# call sinfo and collect data

seconds=$(date +%s) #current unix time

partition_list=$(echo "$sinfo_data" | awk '{print $1}' | tail -n +2 | xargs)	# extract partition list

for partition in ${partition_list}; do
  partition_data=$(echo "$sinfo_data" | grep $partition | xargs)

  A=$(echo "$partition_data" | cut -d ' ' -f 2 | cut -d '/' -f 1 | xargs) \
    && timeout ${curl_timeout} curl -i -u $username:$password -XPOST "$db_endpoint/write?db=$database&precision=s" --data-binary "${metric},partition=${partition},metric=allocated value=${A} $seconds" &> /dev/null
  I=$(echo "$partition_data" | cut -d '/' -f 2 | xargs) \
    && timeout ${curl_timeout} curl -i -u $username:$password -XPOST "$db_endpoint/write?db=$database&precision=s" --data-binary "${metric},partition=${partition},metric=idle value=${I} $seconds" &> /dev/null
  O=$(echo "$partition_data" | cut -d '/' -f 3 | xargs) \
    && timeout ${curl_timeout} curl -i -u $username:$password -XPOST "$db_endpoint/write?db=$database&precision=s" --data-binary "${metric},partition=${partition},metric=other value=${O} $seconds" &> /dev/null
  T=$(echo "$partition_data" | cut -d '/' -f 4 | xargs) \
    && timeout ${curl_timeout} curl -i -u $username:$password -XPOST "$db_endpoint/write?db=$database&precision=s" --data-binary "${metric},partition=${partition},metric=total value=${T} $seconds" &> /dev/null
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
