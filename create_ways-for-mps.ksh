#!/bin/ksh

# written by Michael Maier (s.8472@aon.at)
# 
# 31.12.2015   - intial release
#

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# version 2 as published by the Free Software Foundation.

# FIXME TODO make faster!!!
# bc calls are slow like hell, use interpreter with native double precision support!

###
### Standard help text
###

if [ ! "$1" ] || [ ! "$2" ] || [ "$1" = "-h" ] || [ "$1" = " -help" ] || [ "$1" = "--help" ]
then 
cat <<EOH
Usage: $0 [OPTIONS] infile.osm [-a] outfile.osm

$0 is a program to create new (inner) ways for MPs to enhance routing
outputs OSM XML

OPTIONS:
   -h -help --help     this help text
   \$1 the input file:   has to be OSM XML with only one rel and all ways/nodes (nodes must have no tags)
   [-a]                  Attach content of to output file instead of creating new one (take care youself for validity!)
   \$2 output file name

EOH
exit
fi

###
### variables
###

infile="$1"
if [ "$2" == "-a" ]; then
  attach=1
  outfile="$3"
else
  outfile="$2"
fi

tmpdirname="poly-tmp"
relid=$(grep "<relation id=" "$infile" |cut -d'"' -f 2)
polyfile="$tmpdirname/r$relid.poly"
mnodesfile="$tmpdirname/r$relid-middlenodes.osm"
inodesfile="$tmpdirname/r$relid-innernodes.osm"
debugfile="debug-r$relid.osm"

###
### working part
###

echo "$0 relid: $relid"

if [ ! "$attach" ]; then
  head -n -1 "$infile" > "$outfile"
fi

#head -n 2 "$infile" > "$debugfile"

#reltags=$(grep "<tag k=\"" $infile|grep -v 'ag k="area" v="yes"' | grep -v 'ag k="type" v="multipolygon"')

#ways=$(grep '<member type="way" ref="' "$infile" |cut -d'"' -f 4)
#way_array=($ways)

#nodes=$(grep "nd ref=" "$infile" |cut -d'"' -f 2)
#node_array=($nodes)

set -A node_array

typeset -A lats
typeset -A lons

for i in $nodes; do
  node=$(grep "id=\"$i" $infile)
  lon=$(echo "$node"|sed -e 's/.*lon="\([0-9.]*\)".*/\1/')
  lons[$i]=$lon
  lat=$(echo "$node"|sed -e 's/.*lat="\([0-9.]*\)".*/\1/')
  lats[$i]=$lat
done

echo "node_array: ${node_array[@]}"
echo "lats: ${lats[@]}"
echo "lons: ${lons[@]}"

len_nodes=${#node_array[@]}
echo "nr of nodes overall: $len_nodes"

mkdir -p "$tmpdirname"
#./area2poly.sh $infile > $polyfile
perl osm2poly.pl "$infile" > $polyfile
head -n 2 "$infile" > $mnodesfile

while read -r line
do
  line_array=($line)

  if [ "${line_array[0]}" == "<node" ]; then
    # ${line_array[1]} = id=".."
    continue
  fi
      

  relid=$(echo "$line" | grep -o '<relation id="[0-9-]*"'| cut '-d"' -f 2)
  if [ ! "$relid" ]; then
    continue
  fi
  osmfilter "$infile.mps.osm" --keep="type=multipolygon" --keep-relations="all @id=$relid"  -o="$tmpdirname/r$relid.osm"


done < "$infile"

  
# pre-compute all line segments from way to calculate crossings later
len_segments=$(expr $len - 1)
set -A segments_A
set -A segments_B
set -A segments_C
set -A min_xs
set -A max_xs
set -A min_ys
set -A max_ys
for i in `seq 0 $(expr $len_segments - 1)`; do
  x1=${lons[i]}
  y1=${lats[i]}
  next=$(expr $i + 1)
  x2=${lons[next]}
  y2=${lats[next]}
  A=$(( $y2 - $y1 ))
  B=$(( $x1 - $x2 ))
  segments_A=( ${segments_A[@]} $A )
  segments_B=( ${segments_B[@]} $B )
  segments_C=( ${segments_C[@]} $(( $A * $x1 + $B * $y1 )) )
  # minimal addition/subractions to not cross at endpoints
  #min_xs=( ${min_xs[@]} $(( ( ($x1 < $x2) ? x1 : x2 ) + 0.0000001 )) )
  #max_xs=( ${max_xs[@]} $(( ( ($x1 > $x2) ? x1 : x2 ) - 0.0000001 )) )
  #min_ys=( ${min_ys[@]} $(( ( ($y1 < $y2) ? y1 : y2 ) + 0.0000001 )) )
  #max_ys=( ${max_ys[@]} $(( ( ($y1 > $y2) ? y1 : y2 ) - 0.0000001 )) )
  min_xs=( ${min_xs[@]} $(( ( ($x1 < $x2) ? x1 : x2 ) )) )
  max_xs=( ${max_xs[@]} $(( ( ($x1 > $x2) ? x1 : x2 ) )) )
  min_ys=( ${min_ys[@]} $(( ( ($y1 < $y2) ? y1 : y2 ) )) )
  max_ys=( ${max_ys[@]} $(( ( ($y1 > $y2) ? y1 : y2 ) )) )
done
#echo "segments_A: ${segments_A[@]}"
#echo "segments_B: ${segments_B[@]}"
#echo "segments_C: ${segments_C[@]}"
echo "segments: ${#segments_C[@]}"

new_node_counter=1000000000000
for i_outer in `seq 0 $(expr $len - 4)`;do # outer loop. Start from 0, each node has n-3 connections, so with 0-start to 4
  echo "i_outer: $i_outer, node ${node_array[$i_outer]}"
  #skip next node (+1), is already connected
  inner_node=$(expr $i_outer + 2)
  for i_inner in `seq $inner_node $(expr $len - 2)`; do 
    if [ "$i_outer" == "0" ] && [ "$i_inner" == "$(expr $len - 2)" ]; then
      continue
    fi # special case because the first gets iterated to all and the last connection is implicit
#    echo "connection $i_outer (${node_array[$i_outer]}) to $i_inner (${node_array[$i_inner]})"

    #check for intersection
    x1=${lons[$i_outer]}
    y1=${lats[$i_outer]}
    x2=${lons[$i_inner]}
    y2=${lats[$i_inner]}
    # min(a, b) (((a) < (b)) ? (a) : (b))
    min_x=$(( ( ($x1 < $x2) ? x1 : x2 ) + 0.0000001 ))
    max_x=$(( ( ($x1 > $x2) ? x1 : x2 ) - 0.0000001 ))
    min_y=$(( ( ($y1 < $y2) ? y1 : y2 ) + 0.0000001 ))
    max_y=$(( ( ($y1 > $y2) ? y1 : y2 ) - 0.0000001 ))

#    echo "min: $min_x, x1: $x1, x2: $x2"
    #equation for line Ax+By=C
    A=$(( $y2 - $y1 ))
    B=$(( $x1 - $x2 ))
    C=$(( $A * $x1 + $B * $y1 ))
#    echo "Ax+By=C : $A x + $B y = $C"
    crossing="0"
    for i_segment in `seq 0 $(expr $len_segments - 1)`; do
      #A1 = A, A2 = segments_A[i], B1=B, B2=segments_B[i]
      A1=$A
      A2=${segments_A[$i_segment]}
      B1=$B
      B2=${segments_B[$i_segment]}
      det=$(( $A1 * $B2 - $A2 * $B1 ))
#      echo "det$i_segment: $det"
      if [ "$det" == "0" ]; then
        echo "parallell!"
        continue
      fi
      C1=$C
      C2=${segments_C[$i_segment]}
      x=$(( ( $B2 * $C1 - $B1 * $C2 ) / $det ))
      y=$(( ( $A1 * $C2 - $A2 * $C1 ) / $det ))
#      echo "x: $x, y: $y"
      #min(x1,x2) ≤ x ≤ max(x1,x2) 
      if (( ($min_x < $x) && ($x < $max_x) && ($min_y < $y) && ($y < $max_y) && (${min_xs[$i_segment]} < $x) && ($x < ${max_xs[$i_segment]}) && (${min_ys[$i_segment]} < $y) && ($y < ${max_ys[$i_segment]})  )); then
#        echo "<node id=\"$i_outer$i_inner${i_segment}00\" lat=\"$y\" lon=\"$x\" version=\"1\" timestamp=\"2010-12-22T16:09:27Z\" changeset=\"1\" uid=\"1\" user=\"Me\" />" >> $debugfile
#        echo "crossing found!"
        crossing=1
        break
      fi
    done

    # check if line is inside or outside the polygon
    # create center point, save in .osm file
    # use osmconvert to filter out coordinates outside polygon 
    if [ "$crossing" == "0" ]; then
      mlon=$(( (x1+x2)/2 ))
      mlat=$(( (y1+y2)/2 ))
      echo "<node id=\"$(( ++new_node_counter ))\" lat=\"$mlat\" lon=\"$mlon\" version=\"1\" timestamp=\"2010-12-22T16:09:27Z\" changeset=\"1\" uid=\"1\" user=\"!${node_array[$i_outer]}!${node_array[$i_inner]}!\" />" >> $mnodesfile

#      echo "<node id=\"$new_node_counter\" lat=\"$mlat\" lon=\"$mlon\" version=\"1\" timestamp=\"2010-12-22T16:09:27Z\" changeset=\"1\" uid=\"1\" user=\"Me\" />" >> $debugfile
    fi

  done
done 

echo "</osm>" >> $mnodesfile
osmconvert $mnodesfile -B=$polyfile -o=$inodesfile

wcount=$((20000000000000000 + relid*100000))
while read -r line
do
  nline=$(echo "$line" | grep 'node id=')
  if [ ! "$nline" ]; then
    continue
  fi
  discard=$((wcount++))
  node1=$(echo "$nline" | cut "-d!" -f 2 )
  node2=$(echo "$nline" | cut "-d!" -f 3 )
  
  echo "  <way id=\"$wcount\" timestamp=\"2010-12-23T18:48:05Z\" changeset=\"1\" version=\"1\" uid=\"1\" user=\"polytrianguler\">" >> "$outfile"
  echo "    <nd ref=\"$node1\"/>" >> "$outfile"
  echo "    <nd ref=\"$node2\"/>" >> "$outfile"
  echo "    $reltags" >> "$outfile"
  echo "  </way>" >> "$outfile"

done < "$inodesfile"

if [ ! "$attach" ]; then
  echo "</osm>" >> "$outfile"
fi
#echo "</osm>" >> "$debugfile"
