import os
import sys

from pysnmp.hlapi import *


class Snmp_device:

    TYPE="snmp_device"

    def getSnmpValue(self, host, oid):

        for (errorIndication, errorStatus, errorIndex, varBinds) in getCmd(
            SnmpEngine(), 
            CommunityData(self.snmp_ro_community, mpModel=1), UdpTransportTarget((host, 161)), ContextData(), ObjectType(ObjectIdentity(oid)), lookupMib=False, lexicographicMode=False
            ):
            if errorIndication:
                return 0

            elif errorStatus:
                return 0

            else:
                oid, value = varBinds[0]
                return int(value)

    def __init__(self, host, snmp_ro_community, oid_list, name:str):
        self.host = host
        self.snmp_ro_community = snmp_ro_community
        self.oid_list = oid_list
        self.power = {}
        self.name = name

    def getAllMetrics(self) -> dict:
        # only power consumption defined

        power_cons_dict = {'NodeTotalPower': self.getPowerCons()}
        return power_cons_dict

    def getPowerCons(self):

        device_pwr = 0

        for oid in self.oid_list:
            device_pwr = device_pwr + self.getSnmpValue(self.host, oid)

        return int(device_pwr)

