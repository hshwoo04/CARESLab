
# Reordering Data in chronological order with proper operation annotations
# The program will output a csv file organized by I/O layer.
# Each segment of time will either be a READ, WRITE, or IDLE operation.

import csv
import sys

# Use csv.reader to read values of each column and create list if necessary, manually creating list is okay too
# only requirement is that the data should be organized by the start time in chronological order(low to high)

"""Start times of processes in chronological order"""


start_data = [1 , 3, 5, 6, 9]

"""End times of processes in chronological order"""
end_data = [2, 4, 7, 10, 12]

"""I/O layers of processes in chronological order"""
layers =  [5, 5, 5, 5, 5]

"""Types of processes in chronological order"""
types = [ 1, 1, 1, 1, 1]

"""List of the different I/O Layers"""
dif_Layers = []

def main():
	"""Reordering data to inclue one of the three occuring processes : idle, read, write along with the notation."""
	with open('organized_data.csv', 'wb') as output_file:
    		writer = csv.writer(output_file)
    		writer.writerow(['index'] + ['layer'] + ['start_time_nsec'] + ['exec_time'] + ['end_time_nsec'] + ['operation'])

	for x in layers :
		if x not in dif_Layers :
			dif_Layers.append(x);

	for layer in dif_Layers:
		desired_layer_list = categorization(layers, layer)
		reorder(desired_layer_list, writer)

def get_type(num): 
	# 0, 1, 2, 4, 5, 9, this part needs to be confirmed.
	if (num == 0):
		return "READ"
	elif (num % 2 == 1):
		return "WRITE"
	else:
		return "UNKNOWN"

def addToFile(destFile, what):
	f = open(destFile, 'a').write(what)

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

	start_ind = 0
	end_ind = 0
	layer = layers[layer_list[0]]
	index = 1
	st_last_ind = False
	end_last_ind = False

	while ((start_ind < len(layer_list)) and (end_ind < len(layer_list))) :
		print(start_ind, end_ind)
		if (start_data[layer_list[start_ind]] < end_data[layer_list[end_ind]]): # current start value is smaller than current end value
			start_val = start_data[layer_list[start_ind]]
			end_val = end_data[layer_list[end_ind]]
			temp = get_type(layer_list[start_ind])

			if (start_ind == (len(layer_list) - 1)):
				if (st_last_ind == False):
					end_ind += 1
					st_last_ind = True;
				elif (st_last_ind = True):
					start_val = end_val
					end_val = end_data[layer_list[end_ind + 1]]
					end_ind += 1

			if (start_data[layer_list[start_ind + 1]] < end_data[layer_list[end_ind]]) : # end value is the next start_data value
				end_val = start_data[layer_list[start_ind + 1]]
				start_ind += 1
				
			elif (start_data[layer_list[start_ind + 1]] > end_data[layer_list[end_ind]]): # end value is the current end_data value
				start_ind += 1

			with open('organized_data.csv', 'a') as output_file:
    				writer = csv.writer(output_file)
				writer.writerow([index] + [layer] + [start_val] + [(end_val - start_val)] + [end_val] + [temp])

		elif(end_data[layer_list[end_ind]] < start_data[layer_list[start_ind]]): # current end value is smaller than current start value
			start_val = end_data[layer_list[end_ind]]
			end_val = start_data[layer_list[start_ind]]
			if (end_data[layer_list[end_ind + 1]] < start_data[layer_list[start_ind]]): # end value is the next end_data value
				end_val = end_data[layer_list[end_ind + 1]]
				temp = get_type(layer_list[end_ind])
				end_ind += 1

			elif (end_data[layer_list[end_ind + 1]] > start_data[layer_list[start_ind]]): # end value is the current start_data value(IDLE)
				temp = "IDLE"
				end_ind += 1
		
			with open('organized_data.csv', 'a') as output_file:
    				writer = csv.writer(output_file)
				writer.writerow([index] + [layer] + [start_val] + [(end_val - start_val)] + [end_val] + [temp])

		index += 1


main()