#!/usr/bin/env python3

import urllib3
import urllib.parse
import requests
import sys
import concurrent.futures
import time

from datetime import datetime

from redfishwrapper.intelRedfish import *
from redfishwrapper.supermicroRedfish import *
from snmpwrapper.snmpDevice import *

import ClusterShell

from influxdb import InfluxDBClient  # pip3 install influxdb --upgrade

from config import *

logging.basicConfig(level=logging.WARNING)


def get_config_path():

    # get the path to our configuration:
    this_script_path = os.path.abspath(os.path.dirname(sys.argv[0]))
    config_file_name = str(os.path.splitext(
        os.path.basename(sys.argv[0]))[0]) + ".yaml"
    config_file_path = this_script_path + "/" + config_file_name
    return(config_file_path)


if __name__ == "__main__":

    # parse config:
    config = Config(yamlConfigFilePath=get_config_path())

    #log

    if os.path.exists(config.accountlog):
        append_write_flag = 'a'  # append if already exists
    else:
        append_write_flag = 'w'  # make a new file if not

    logfile = open(config.accountlog, append_write_flag)
    monitoredObjects = []

    # get list of managers objects:
    for obj in config.dataDict:
        obj_model = config.dataDict[obj]['model']
        if obj_model == "intel_v1":
            logging.debug(f"added intel object {obj}")
            ipmiObject = IntelRedfish(
                ipmi_host=config.dataDict[obj]['manager'],
                ipmi_user=config.dataDict[obj]['ipmi_user'],
                ipmi_pass=config.dataDict[obj]['ipmi_pass'],
                verifySSL=False,
                name = obj
            )
            monitoredObjects.append(ipmiObject)
        elif obj_model == "supermicro_v1":
            logging.debug(f"added supermicro_v1 object {obj}")
            ipmiObject = SupermicroRedfish(
                ipmi_host=config.dataDict[obj]['manager'],
                ipmi_user=config.dataDict[obj]['ipmi_user'],
                ipmi_pass=config.dataDict[obj]['ipmi_pass'],
                verifySSL=False,
                name = obj
            )
            monitoredObjects.append(ipmiObject)
        elif obj_model == "snmp_v1":
            logging.debug(f"added snmp_v1 object {obj}")
            ipmiObject = Snmp_device(
                host=config.dataDict[obj]['manager'],
                snmp_ro_community=config.dataDict[obj]['ro_community'],
                oid_list=config.dataDict[obj]['snmp_oids'],
                name = obj
            )
            monitoredObjects.append(ipmiObject)
        else:
            #pass
            raise Exception(f"object {obj} has not implemented model.")

    client = InfluxDBClient(config.db_host, config.db_port, config.http_user, config.http_pass, config.db)
    last_write_timestamp = 0

    while(True):

        total_power = 0
        data = []
        measurement_name = 'oob_monitoring'
        tag_cluster = "koios"
        t_main_start = int(time.time() * 1000)  # milliseconds

        ipmiobject_cnt = 0
        ipmis_reached_nodeset = ClusterShell.NodeSet.NodeSet()

        futures = []
        names = []
        results = {}

        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            logging.debug("submitting...")
            for obj in monitoredObjects:
                futures.append(executor.submit(obj.getAllMetrics))
                names.append(obj.name)
            logging.debug("..submitted.")
            for future,name in zip(futures,names):
                try:
                    thread_result = future.result(timeout=5)
                except Exception as exc:
                    logging.warning(f"bad, future failed.")
                else:
                    results[name] = thread_result
                    ipmiobject_cnt = ipmiobject_cnt + 1
                    ipmis_reached_nodeset.add(name)

        for item in results:

            total_power = total_power + results[item]['NodeTotalPower']

            logging.debug("====================================================")
            logging.debug(f"item: {item}")
            logging.debug(results[item])
            logging.debug("====================================================")

            variables_string = ""

            for metric in results[item]:
                metric_string = metric.replace(" ", "_")
                variables_string = variables_string + f"{metric_string}={results[item][metric]}" + " "

            variables_string = variables_string.strip().replace(" ",",")
                
            data_string = f"{measurement_name},cluster={tag_cluster},object_name={item} {variables_string} {int(t_main_start)}"
            logging.debug(f"data_string=\"{data_string}\"")
            data.append(data_string)



        # write total cluster power consumption to influx        
        metric_string = 'platform_power'
        data_string = f"{measurement_name},cluster={tag_cluster},object_name=cluster_total {metric_string}={total_power} {int(t_main_start)}"
        logging.debug(f"data_string=\"{data_string}\"")
        data.append(data_string)        

        logging.debug(f"total_power .. {total_power}")

        t_since_last_write = int(time.time() - last_write_timestamp)
        logging.debug(f"t_since_last_write: {t_since_last_write}")

        if ( t_since_last_write > config.accountperiod ):
            stats_string = f"total cluster power: {str(total_power)} W, devices reached: {str(ipmiobject_cnt)} - {str(ipmis_reached_nodeset)}"
            date_time_string = datetime.today().strftime('%Y-%m-%d-%H:%M:%S')
            log_line_string = date_time_string + "\t" + stats_string + "\n"
            logfile.write(log_line_string)
            logfile.flush()
            last_write_timestamp = int(time.time())
            print(stats_string) #print it to stdout to have it in journal.
        
        # write data to DB:
        client.write_points(data, database=config.db, time_precision='ms', batch_size=1000, protocol='line')