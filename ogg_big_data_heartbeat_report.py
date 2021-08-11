#!/bin/python3
# Python program to read ogg heartbeat history json file

import json
import time
import datetime
import os
import glob
import sys, getopt

def main(argv):
  # Initialize Variables
  vLagJsonDir = ''
  try:
    opts, args = getopt.getopt(argv,"h:j:",["jsondir="])
    if len(opts) == 0:
      print('Script Usage: ogg_big_data_heartbeat_report.py -j <jsondir>')
      sys.exit(1)
  except getopt.error as err:
    print('Script Usage: ogg_big_data_heartbeat_report.py -j <jsondir>')
    sys.exit(2)
  for opt, arg in opts:
    if opt == '-h':
      print('Script Usage: ogg_big_data_heartbeat_report.py -j <jsondir>')
      sys.exit()
    #elif opt in ("-j", "--jsondir"):
    elif opt == '-j':
      vLagJsonDir = arg
    elif opt == '--jsondir':
      vLagJsonDir = arg

  vTotLag = 0
  vTotJsonRecords = 0
  vTotLag_1hour = 0
  vTotJsonRecords_1hour = 0
  vTotLag_4hour = 0
  vTotJsonRecords_4hour = 0
  vTotLag_8hour = 0
  vTotJsonRecords_8hour = 0
  vTotLag_24hour = 0
  vTotJsonRecords_24hour = 0
  now = time.mktime(datetime.datetime.now().timetuple())
  if vLagJsonDir == "":
    vLagJsonDir = "/u01/app/oracle/product/oggBd/19.1/gg_1/dirtmp/"
    print('JSON Dir defaulted to: ' + str(vLagJsonDir))
  else:
    print('JSON Dir is: ' + str(vLagJsonDir))
  lag_records = []
  heartbeat_timestamp_records = []
  replication_path_records = []

  # Opening JSON file
  for filename in glob.glob(vLagJsonDir + '/*-hb-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].json'):
    #print(os.path.join(vLagJsonDir + "/", filename))
    f = open(os.path.join(vLagJsonDir + "/", filename))

    # returns JSON object as
    # a dictionary
    data = json.load(f)

    # Iterating through the json
    # list
    for i in data['records']:
      vIncomingTs = time.mktime(datetime.datetime.strptime(i['incomingHeartbeatTs'][:-3],"%Y-%m-%d %H:%M:%S.%f").timetuple())
      vOutgoingTs = time.mktime(datetime.datetime.strptime(i['outgoingReplicatTs'][:-3],"%Y-%m-%d %H:%M:%S.%f").timetuple())
      vIncomingHeartbeatTs = datetime.datetime.strptime(i['incomingHeartbeatTs'][:-3],"%Y-%m-%d %H:%M:%S.%f").strftime('%Y-%m-%d %H:%M')
      heartbeat_timestamp_records.append(vIncomingHeartbeatTs)
      #print(str(now - vOutgoingTs))
      if (now - vOutgoingTs) <= 3600:
        vTotLag_1hour = vTotLag_1hour + (vOutgoingTs - vIncomingTs)
        vTotJsonRecords_1hour = (vTotJsonRecords_1hour + 1)
        lag_records.append(i['incomingExtract'] + " => " + i['incomingRoutingPath'] + " => " + i['incomingReplicat'] + " | " + vIncomingHeartbeatTs + " | " + str(vOutgoingTs - vIncomingTs))
        replication_path_records.append(i['incomingExtract'] + " => " + i['incomingRoutingPath'] + " => " + i['incomingReplicat'])
      elif (now - vOutgoingTs) <= 14400:
        vTotLag_4hour = vTotLag_4hour + (vOutgoingTs - vIncomingTs)
        vTotJsonRecords_4hour = (vTotJsonRecords_4hour + 1)
      elif (now - vOutgoingTs) <= 28800:
        vTotLag_8hour = vTotLag_8hour + (vOutgoingTs - vIncomingTs)
        vTotJsonRecords_8hour = (vTotJsonRecords_8hour + 1)
      elif (now - vOutgoingTs) <= 86400:
        vTotLag_24hour = vTotLag_24hour + (vOutgoingTs - vIncomingTs)
        vTotJsonRecords_24hour = (vTotJsonRecords_24hour + 1)

      vTotLag = vTotLag + (vOutgoingTs - vIncomingTs)
      vTotJsonRecords = (vTotJsonRecords + 1)

    # Closing file
    f.close()

  vMaxHeartbeatTs = datetime.datetime.strptime(max(heartbeat_timestamp_records), '%Y-%m-%d %H:%M')
  vMinHeartbeatTs = datetime.datetime.strptime(min(heartbeat_timestamp_records), '%Y-%m-%d %H:%M')
  vTimeDiff = round((vMaxHeartbeatTs - vMinHeartbeatTs).total_seconds()/86400,1)

  # Print the array of Extract Lag Information

  replication_path_records = list(dict.fromkeys(replication_path_records))
  print('\nReplication Paths:')
  for elem in replication_path_records:
    print(elem)

  print('\nCombined Lag Data for Replication Paths:\n')
  # Print Average Lag Over Entire Recordset
  if vTotJsonRecords_1hour > 0:
    print("Average Lag over the past hour: " + str(vTotLag_1hour // vTotJsonRecords_1hour) + " seconds")
  if vTotJsonRecords_4hour > 0:
    print("Average Lag over the past 4 hours: " + str(vTotLag_4hour // vTotJsonRecords_4hour) + " seconds")
  if vTotJsonRecords_8hour > 0:
    print("Average Lag over the past 8 hours: " + str(vTotLag_8hour // vTotJsonRecords_8hour) + " seconds")
  if vTotJsonRecords_24hour > 0:
    print("Average Lag over the past 24 hours: " + str(vTotLag_24hour // vTotJsonRecords_24hour) + " seconds")
  print("Average Lag over the dataset (" + str(vTimeDiff) + " Days): " + str(vTotLag // vTotJsonRecords) + " seconds")

if __name__ == "__main__":
  if len(sys.argv) < 1:
    print('Script Usage: ogg_big_data_heartbeat_report.py -j <jsondir>')
    sys.exit(2)
  else:
    main(sys.argv[1:])