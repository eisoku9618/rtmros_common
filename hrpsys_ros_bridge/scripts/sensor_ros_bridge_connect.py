#!/usr/bin/python

# This program is used to connect RosBridge sensor ports with simulator or RobotHardware sensor ports based on ModelLoader information.

# use hrpsys/scripts/hrpsys.py file
import roslib;
import sys; sys.path.insert (0, roslib.packages.get_pkg_dir('hrpsys')+'/scripts');
from hrpsys import *

program_name = '[sensor_ros_bridge_connect.py] '

def connecSensorRosBridgePort(url, rh, bridge):
    sensors = map(lambda x : x.sensors, filter(lambda x : len(x.sensors) > 0, getBodyInfo(url)._get_links()))
    for sen in sum(sensors, []): # sum is for list flatten
        print sen.name
        if sen.type == 'Acceleration':
            print program_name, "connect ", rh.port('acc'), bridge.port("gsensor")
            connectPorts(rh.port('acc'), bridge.port("gsensor"))
        elif sen.type == 'RateGyro':
            print program_name, "connect ", rh.port('rate'), bridge.port('gyrometer')
            connectPorts(rh.port('rate'), bridge.port('gyrometer'))
        elif sen.type == 'Force':
            print program_name, "connect ", rh.port(sen.name), bridge.port(sen.name)
            connectPorts(rh.port(sen.name), bridge.port(sen.name))
        else:
            continue

def initSensorRosBridgeConnection(url, simulator_name, rosbridge_name):
    ms = None
    bridge = None
    rh = None
    while ms == None :
        time.sleep(1);
        ms = rtm.findRTCmanager()
        print "[hrpsys.py] wait for RTCmanager : ",ms
    while rh == None :
        time.sleep(1);
        rh = rtm.findRTC(simulator_name)
        print "[hrpsys.py] wait for ", simulator_name, " : ",rh
    while bridge == None :
        time.sleep(1);
        bridge = rtm.findRTC(rosbridge_name)
        print "[hrpsys.py] wait for ", rosbridge_name, " : ",bridge
    connecSensorRosBridgePort(url, rh, bridge)

if __name__ == '__main__':
    print program_name, "start"
    if len(sys.argv) > 3 :
        initSensorRosBridgeConnection(sys.argv[1], sys.argv[2], sys.argv[3])
    else :
        print program_name, " requires url, simulator_name, rosbridge_name"
