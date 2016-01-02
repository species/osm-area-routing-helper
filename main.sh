#!/bin/bash

# written by Michael Maier (s.8472@aon.at)
# 
# 02.01.2015   - intial release
#

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# version 2 as published by the Free Software Foundation.

###
### Standard help text
###

if [ ! "$1" ] || [ ! "$2" ] || [ "$1" = "-h" ] || [ "$1" = " -help" ] || [ "$1" = "--help" ]
then 
cat <<EOH
Usage: $0 [OPTIONS] 

$0 is a program to add ways connecting all nodes for polygons for a given osm file for better routing

OPTIONS:
   -h -help --help     this help text
   \$1 the input file: has to be an osm file
   \$2 output file name

EOH
fi

###
### variables
###

infile="$1"
outfile="$2"

tmpdirname="poly-tmp"

###
### working part
###

osmconvert "$infile" -o="$infile.o5m"
osmfilter "$infile.o5m" --keep=" ( highway= and area=yes ) or ( highway= and type=multipolygon ) " --keep-node-tags="all blubb=" -o="$infile.filtered.o5m"

head -n -1 "$infile.areas.osm" > "$outfile"

#1st part: only areas
osmfilter "$infile.filtered.o5m"  --drop-relations -o="$infile.a1.o5m"
osmfilter "$infile.a1.o5m" --keep-ways="area=yes"  -o="$infile.areas.osm"
rm "$infile.a1.o5m"

while read -r line
do
  wayid=$(echo "$line" | grep -o '<way id="[0-9-]*"'| cut '-d"' -f 2)
  if [ ! "$wayid" ]; then
    continue
  fi

  osmfilter "$infile.areas.osm" --keep-ways="@id=$wayid"  -o=$tmpdirname/w$wayid.osm
  ./create_ways.ksh "$tmpdirname/w$wayid.osm" -a "$outfile"

done < "$infile.areas.osm"
#FIXME not very efficient, calls grep for every line
# better would be something like this  grep ... | cut | while read  - read somewhere this starts a subshell?

rm "$infile.areas.osm"

#2nd part: MPs: todo
osmfilter "$infile.filtered.o5m" --keep-way-tags="all blubb=" -o="$infile.mps.osm"

while read -r line
do
  relid=$(echo "$line" | grep -o '<relation id="[0-9-]*"'| cut '-d"' -f 2)
  if [ ! "$relid" ]; then
    continue
  fi
  osmfilter "$infile.mps.osm" --keep="type=multipolygon" --keep-relations="all @id=$relid"  -o="$tmpdirname/r$relid.osm"


done < "$infile.mps.osm"

# end
echo "</osm>" >> "$outfile"
#rm "$infile.o5m"
#rm "$infile.filtered.o5m"

