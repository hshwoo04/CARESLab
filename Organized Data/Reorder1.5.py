# Reordering Data in chronological order with proper operation annotations
# The program will output a csv file organized by I/O layer.
# Each segment of time will either be a READ, WRITE, or IDLE operation.

import csv
import sys

"""start times of processes"""
start_data = []

"""End times of processes"""
end_data = []

"""I/O layers of processes"""
layers =  []

"""Types of processes"""
types = []

"""List of the different I/O Layers"""
dif_Layers = []

layer_start_times =[]

def main():
	"""Reordering data to include one of the three occuring processes : idle, read, write along with the notation."""
	layer_count = 0

	for x in layers :
		if x not in dif_Layers :
			dif_Layers.append(x);

	for x in dif_Layers :
		minVal = sys.maxint
		for y in range(len(layers) - 1) :
			if (x == layers[y]) :
				if start_data[y] < minVal :
					minVal = start_data[y]
		layer_start_times.append(minVal)

	for layer in dif_Layers:
		desired_layer_list = categorization(layers, layer)
		reorder(desired_layer_list, layer_count)
		layer_count += 1

def getOperation(st_index, isIdle, operation): 
	if (isIdle) : 
		return "idle"
	else:
		if int(operation) == 0 :
			return "read"
		else:
			return "write"

def categorization(layers, desired_layer) :
	"""This function categorizes the data by its layer and chronologically and returns a list with the index of the desired layer."""
	temp_list = []
	i = 0
	while (i < len(layers)):
		if (layers[i] == desired_layer) :
			temp_list.append(i);
		i += 1

	return temp_list

def getKey(item):
	return item[1]

def reorder(layer_list, cnt):
	"""This function organizes the desired layer and writes it onto a csv file"""

	data = []
	num = 0

	for index in layer_list:					# creates a list of the specified values for the I/O Layer
		data.append((index, start_data[index], 0, types[index])) 
		data.append((index, end_data[index], 1, types[index]))

	layer = layers[data[0][0]]	

	with open('organized_data_layer' + layer + '.csv' , 'wb') as output_file:
    		writer = csv.writer(output_file)
    		writer.writerow(['index'] + ['layer'] + ['operation'] + ['exec_time'])
    		writer.writerow(['0'] + [layer] + ['idle'] + [(layer_start_times[cnt] - min(layer_start_times))])

	sortedData = sorted(data, key = getKey)	
	while num < len(sortedData) - 1:
		min_val = sortedData[num]
		sec_min_val = sortedData[num + 1]
		start_val = min_val[1]
		end_val = sec_min_val[1]
		isIdle = False
		if (min_val[2] == 1 and sec_min_val[2] == 0) :
			isIdle = True

		operation = getOperation(min_val[0], isIdle, min_val[3])

		with open('organized_data_layer' + layer + '.csv', 'a') as output_file:
	    		writer = csv.writer(output_file)
			writer.writerow([num + 1] + [layer] + [operation]  + [(int(end_val) - int(start_val))])
		num += 1


# Use csv.reader to read values of each column and create list if necessary, manually creating list is okay too
# The input data must be in windows csv format.

with open('data.csv', 'r') as dataFile: # need to change the read file name as necessary
		reader = csv.reader(dataFile)
		dataList = list(reader)

del dataList[0]

for data in dataList :
	    start_data.append( (int (data[1]) ) * 1000000000 + (int( data[2]) ) )
	    end_data.append( (int(data[1])) * 1000000000 + (int(data[2])) + (int(data[3]))  )
	    layers.append(data[7])
	    types.append(data[8])

main()