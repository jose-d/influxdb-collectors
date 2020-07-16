# Slurm metric writer

This collector written in BASH collects data from slurm and exports them into influxdb using the HTTP api.

![Example of visualization in Grafana](/slurm_metric_writer/doc/14day_utilization_screenshot.png)
Example Grafana visualization using slurm.node_status data collected by this script. ([Panel Carpet plot by Petr Slavotínek](https://grafana.com/plugins/petrslavotinek-carpetplot-panel) ) 

Query: ```SELECT sum("value") FROM "slurm.node_status" WHERE ("metric" = 'ALLOCATED') AND $timeFilter GROUP BY time(1m) fill(null)```

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

## Configuration and install

Just modify the variables at the beginning of the script to match your influxDB setup, execution can be managed in cron - example line in crontab:

```
* * * * * /bin/bash /usr/local/sw/monitors/influxdb-collectors/slurm_metric_writer/collect.bash &> /dev/null
```

![Example of Grafana visualisation](/slurm_metric_writer/doc/Screenshot_2020-07-16%20Slurm%20stats%20-%20Grafana.png)

## Compatibility

Tested with Slurm 17.11.7, 18.08.8;
