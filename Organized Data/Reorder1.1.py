
# Reordering Data in chronological order with proper operation annotations
# The program will output a csv file organized by I/O layer.
# Each segment of time will either be a READ, WRITE, or IDLE operation.

import csv
import sys

# Best if dif_layers is filled out manually

start_data = []

"""End times of processes in chronological order"""
end_data = []

"""I/O layers of processes in chronological order"""
layers =  []

"""Types of processes in chronological order"""
types = []

"""List of the different I/O Layers"""
dif_Layers = []




def main():
	"""Reordering data to inclue one of the three occuring processes : idle, read, write along with the notation."""
	with open('organized_data.csv', 'wb') as output_file:
    		writer = csv.writer(output_file)
    		writer.writerow(['index'] + ['layer'] + ['operation'] + ['exec_time'] + ['start_time_nsec'] + ['end_time_nsec'] )

	for x in layers :
		if x not in dif_Layers :
			dif_Layers.append(x);

	for layer in dif_Layers:
		desired_layer_list = categorization(layers, layer)
		reorder(desired_layer_list, writer)

def getOperation(st_index, isIdle, operation): 
	# 0, 1, 2, 4, 5, 9, this part needs to be confirmed.
	if (isIdle) : 
		return "idle"
	else:
		if operation == 0 :
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


def reorder(layer_list, write_file):
	"""This function organizes the desired layer and writes it onto a csv file"""

	data = []
	num = 0

	for index in layer_list:					# creates a list of the specified values for the I/O Layer
		data.append((index, layers[index], start_data[index], 0, types[index])) 
		data.append((index, layers[index], end_data[index], 1, types[index]))

	while len(data) != 1:
		min_val = data[0]
		sec_min_val = data[1]
		for data_tuple in data:
			if  data_tuple[2] < min_val[2]: # fix this part since the first value might be the minimum
				sec_min_val = min_val
				min_val = data_tuple

		data.remove(min_val)

		layer = min_val[1]
		start_val = min_val[2]
		end_val = sec_min_val[2]
		isIdle = False
		if (min_val[3] == 1 and sec_min_val[3] == 0) :
			isIdle = True

		operation = getOperation(min_val[0], isIdle, min_val[4])
		with open('organized_data.csv', 'a') as output_file:
	    		writer = csv.writer(output_file)
			writer.writerow([num] + [layer] + [operation]  + [(int(end_val) - int(start_val))] + [start_val] + [end_val])
		num += 1

# Use csv.reader to read values of each column and create list if necessary, manually creating list is okay too
# The input data must be in windows csv format.

with open('data.csv', 'r') as dataFile:
		reader = csv.reader(dataFile)
		dataList = list(reader)

del dataList[0]

for data in dataList :
	start_data.append(int(data[6]))
	end_data.append(int(data[8]))
	layers.append(data[4])
	types.append(data[5])

main()