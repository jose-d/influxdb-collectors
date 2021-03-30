import logging
import os
import yaml
import sys
from ClusterShell import NodeSet


class Config:

    POSSIBLE_ATTRS = ["ipmi_user", "ipmi_pass", "model", "snmp_oids", "ro_community" ]

    def __init__(self, yamlConfigFilePath):

        logging.basicConfig(stream=sys.stdout, level=logging.ERROR)

        if os.path.isfile(yamlConfigFilePath):
            config_file = open(yamlConfigFilePath, 'r')
            conf = yaml.safe_load(config_file)
            config_file.close()

        else:
            raise Exception("config.py: No config file found")

        """ 
        we iterate ver item in endpoints list, it's like:
        {'names': 'n[15-27]', 'managers': 'n[15-27]-ipmi', 'ipmi_user': 'root', 'ipmi_pass': 'NoWay', 'model': 'intel_v1'}
        {'names': 'n3', 'managers': 'n3-ipmi', 'ipmi_user': 'root', 'ipmi_pass': 'NoWay', 'model': 'intel_v1'}
        {'names': 'n[1,2,4-14]', 'managers': 'n[1,2,4-14]-ipmi', 'ipmi_user': 'root', 'ipmi_pass': 'NoWay', 'model': 'intel_v1'}
        {'names': 'n[28]', 'managers': 'n[28]-ipmi', 'ipmi_user': 'ADMIN', 'ipmi_pass': 'NoWay', 'model': 'supermicro_v1'}
        {'names': 'isw1', 'managers': 'isw1', 'model': 'snmp', 'snmp_oids': ['.1.3.6.1.2.1.99.1.1.1.4.602240030', '.1.3.6.1.2.1.99.1.1.1.4.601240030']}
        """

        self.dataDict = {}

        self.db_host = conf['influxdb']['db_host']
        self.db_port = conf['influxdb']['db_port']
        self.http_user = conf['influxdb']['http_user']
        self.http_pass = conf['influxdb']['http_pass']
        self.db = conf['influxdb']['db']

        self.accountlog = conf['accounting']['logfile']
        self.accountperiod = conf['accounting']['logperiod']

        for endpointDef in conf['endpoints']:

            namesList = NodeSet.expand(endpointDef['names'])
            managersList = NodeSet.expand(endpointDef['managers'])

            if len(namesList) != len(managersList):
                raise Exception(f"Configuration error: Nodesets {endpointDef['names']} and {endpointDef['managers']} have different size.")

            for name, manager in zip(namesList,managersList):
                self.dataDict[name] = {}
                self.dataDict[name]['manager'] = manager

                for attr in self.POSSIBLE_ATTRS:
                    if attr in endpointDef:
                        self.dataDict[name][attr] = endpointDef[attr]