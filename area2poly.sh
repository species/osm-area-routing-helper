#!/bin/bash

# written by Michael Maier (s.8472@aon.at)
# 
# 31.12.2015   - intial release
#

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# version 2 as published by the Free Software Foundation.

###
### Standard help text
###

if [ ! "$1" ] || [ "$1" = "-h" ] || [ "$1" = " -help" ] || [ "$1" = "--help" ]
then 
cat <<EOH
Usage: $0 [OPTIONS] 

$0 is a program to convert osm files with a single (closed) way into a .poly file
outputs the content on stdout.

OPTIONS:
   -h -help --help     this help text
   \$1 the input file: has to be OSM XML with only one way and all nodes

EOH
exit
fi

###
### variables
###

infile="$1"

###
### working part
###

echo "$infile"
echo "1"

nodes="`grep "ref=" "$infile" |cut -d'"' -f 2`"
for i in $nodes; do
  node=$(grep "id=\"$i" $infile)
  lon=$(echo "$node"|sed -e 's/.*lon="\([0-9.]*\)".*/\1/')
  lat=$(echo "$node"|sed -e 's/.*lat="\([0-9.]*\)".*/\1/')
  echo -e "\t$lon\t$lat"
done

echo "END"
echo "END"
