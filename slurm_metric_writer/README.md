# Slurm metric writer

This collector written in BASH collects data from slurm and exports them into influxdb using the HTTP api.

![Example of visualization in Grafana](/slurm_metric_writer/doc/14day_utilization_screenshot.png)
Example Grafana visualization using data collected by this script.

## Collected metrics

### `slurm.partition_usage`
- partition-level statistics of nodes in `allocated`,`idle`,`other` and `total` status
- ( parsed ```sinfo -O partitionname,nodeaiot``` )

### `slurm.queue_stats`
- amount of jobs in slurm queue in state `R` and `PD`
- ( parsed ```squeue -t R --noheader```, ```squeue -t PD --noheader```  )

### `slurm.node_stats`
- drained/draining nodes count
- ( parsed ```sinfo -R --noheader``` )

### `slurm.node_status`
- node state - `ALLOCATED|IDLE|MIXED|RESERVED`
- ( parsed ```scontrol show nodes -o``` )

## Configuration

Just modify the variables at the beginning of the script.

## Compatibility

Tested with Slurm 17.11.7.
