# This program will output a csv file organized by I/O layer.
# Calculates the throughput of each process (kilobytes/second)


import csv
import sys

"""start times of processes"""
start_data = []

"""Execution times of processes"""
exec_data = []

"""I/O layers of processes"""
layers =  []

"""Data size of processes"""
sizes = []

"""Layers used in all processes"""
dif_Layers = []

def main():
	"""Outputs the bandwidth (data size/time) of each process"""

	for x in layers :
		if x not in dif_Layers :
			dif_Layers.append(x);

	for layer in dif_Layers:
		desired_layer_list = categorization(layers, layer)
		write(desired_layer_list)	

def categorization(layers, desired_layer) :
	"""This function categorizes the data by its layer and chronologically and returns a list with the index of the desired layer."""
	temp_list = []
	i = 0
	while (i < len(layers)):
		if (layers[i] == desired_layer) :
			temp_list.append(i);
		i += 1

	return temp_list


def write(layer_list):
	"""This function calculates the throughput and writes it onto a csv file"""
	count = 0
	layer = layers[layer_list[0]]
	with open('organized_data_layer' + layer + '.csv' , 'wb') as output_file:
    		writer = csv.writer(output_file)
    		writer.writerow(['index'] + ['layer'] + ['start_time_nsec'] + ['bandwidth(kb/s)'])	
   
	while count < (len(layer_list)):

		sttime = start_data[layer_list[count]]
		bdw = ((sizes[layer_list[count]] / 1024.0) / (exec_data[layer_list[count]] / 1000000000.0)) # unit is kilobytes/second
		
		with open('organized_data_layer' + layer + '.csv', 'a') as output_file:
	    		writer = csv.writer(output_file)
			writer.writerow([count] + [layer] + [sttime]  + [bdw])

		count += 1


# Use csv.reader to read values of each column and create a list
# The input data must be in windows csv format.

with open('data.csv', 'r') as dataFile: # need to change the read file name as necessary
		reader = csv.reader(dataFile)
		dataList = list(reader)

del dataList[0]

for data in dataList :
	    start_data.append( (int (data[1]) ) * 1000000000 + (int( data[2]) ) )
	    exec_data.append(int(data[3]))
	    layers.append(data[7])
	    sizes.append(int(data[13]))

main()