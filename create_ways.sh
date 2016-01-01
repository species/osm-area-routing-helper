#!/bin/bash

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
Usage: $0 [OPTIONS] infile.osm outfile.osm

$0 is a program to create new (inner) ways for areas to enhance routing
outputs OSM XML

OPTIONS:
   -h -help --help     this help text
   \$1 the input file: has to be OSM XML with only one way and all nodes (nodes must have no tags)
   \$2 output file name

EOH
exit
fi

###
### variables
###

infile="$1"
outfile="$2"


###
### working part
###

head -n -1 $infile > $outfile
head -n 2 $infile > debug.osm

waytags=$(grep "<tag k=\"" $infile|grep -v 'ag k="area" v="yes"')

nodes="`grep "ref=" "$infile" |cut -d'"' -f 2`"
wayid="`grep "way id=" "$infile" |cut -d'"' -f 2`"
node_array=($nodes)
lats=()
lons=()
for i in $nodes; do
  node=$(grep "id=\"$i" $infile)
  lon=$(echo "$node"|sed -e 's/.*lon="\([0-9.]*\)".*/\1/')
  lons=(${lons[@]} $lon)
  lat=$(echo "$node"|sed -e 's/.*lat="\([0-9.]*\)".*/\1/')
  lats=(${lats[@]} $lat)
done

echo "node_array: ${node_array[@]}"
echo "lats: ${lats[@]}"
echo "lons: ${lons[@]}"

len=${#node_array[@]}
echo "len: $len"

# pre-compute all line segments from way to calculate crossings later
len_segments=$(expr $len - 1)
segments_A=()
segments_B=()
segments_C=()
min_xs=()
max_xs=()
min_ys=()
max_ys=()
for i in `seq 0 $(expr $len_segments - 1)`; do
  x1=${lons[$i]}
  y1=${lats[$i]}
  next=$(expr $i + 1)
  x2=${lons[$next]}
  y2=${lats[$next]}
  A=$( echo "scale=19; $y2 - $y1" | bc -l )
  B=$( echo "scale=19; $x1 - $x2" | bc -l)
  segments_A=( ${segments_A[@]} $A )
  segments_B=( ${segments_B[@]} $B )
  segments_C=( ${segments_C[@]} $( echo "scale=19; $A * $x1 + $B * $y1" | bc -l) )
  # minimal addition/subractions to not cross at endpoints
  min_xs=( ${min_xs[@]} $( echo "scale=19; if ($x1 < $x2) {$x1 + 0.0000001} else {$x2 + 0.0000001}" | bc -l ) )
  max_xs=( ${max_xs[@]} $( echo "scale=19; if ($x1 > $x2) {$x1 - 0.0000001} else {$x2 - 0.0000001}" | bc -l ) )
  min_ys=( ${min_ys[@]} $( echo "scale=19; if ($y1 < $y2) {$y1 + 0.0000001} else {$y2 + 0.0000001}" | bc -l ) )
  max_ys=( ${max_ys[@]} $( echo "scale=19; if ($y1 > $y2) {$y1 - 0.0000001} else {$y2 - 0.0000001}" | bc -l ) )
done
echo "segments_A: ${segments_A[@]}"
echo "segments_B: ${segments_B[@]}"
echo "segments_C: ${segments_C[@]}"

# in which direction is the graph? CW or CCW?
# in node order, are the sum of right-hand angles bigger or the sum of left-hand-angles?
# if right-hand angles are bigger, it is CCW, else otherwise.
#
# how to calculate an angle? we have three points: center, last and forward
# alpha = atn (Δy/Δx)

segments_dx=()
segments_dy=()
segments_angle=() # angle from start position, positive value
for i in `seq 0 $(expr $len_segments - 1)`; do
  x1=${lons[$i]}
  y1=${lats[$i]}
  echo "<node id=\"9${i}99\" lat=\"$y1\" lon=\"$x1\" version=\"1\" timestamp=\"2010-12-22T16:09:27Z\" changeset=\"1\" uid=\"1\" user=\"Me\" />" >> debug.osm
  next=$(expr $i + 1)
  x2=${lons[$next]}
  y2=${lats[$next]}
  delta_x=$( echo "scale=19; $x2 - $x1" | bc -l)
  delta_y=$( echo "scale=19; $y2 - $y1" | bc -l)
  segments_dx=( ${segments_dx[@]} $delta_x )
  segments_dy=( ${segments_dy[@]} $delta_y )

  # note: these angles are distorted by projection, do not correspond to e.g. mercartor! But they are linear, and therefore can be used for comparison
  angle=$( echo "scale=19; a ( $delta_y / $delta_x ) / a(1) * 45" | bc -l) 

  # quadrants: needed for adjusting results from atan (1 = NE, 2 = NW, 3 = SW, 4 = SE
  quadrant=$( echo "scale=19; if ( $delta_y >= 0 ) { if ( $delta_x >= 0 ) {1} else {2} } else { if ( $delta_x >= 0 ) {4} else {3} }" | bc -l )
  if [ "$quadrant" == "2" ] || [ "$quadrant" == "3" ]; then
    angle=$( echo "180 + $angle" | bc -l )
  fi 
  if [ "$quadrant" == "4" ]; then
    angle=$( echo "360 + $angle" | bc -l )
  fi
  echo "$i: [$quadrant] $angle"
  segments_angle=( ${segments_angle[@]} $angle )

  #angle between two vectors is acos ( (a1b1 + a2b2)/ sqrt ( ( a1²+a2²)(b1²+b2²) ) ) - derivet from dot-product
  
done


for i_outer in `seq 0 $(expr $len - 4)`;do # outer loop. Start from 0, each node has n-3 connections, so with 0-start to 4
  echo "i_outer: $i_outer, node ${node_array[$i_outer]}"
  #skip next node (+1), is already connected
  inner_node=$(expr $i_outer + 2)
  for i_inner in `seq $inner_node $(expr $len - 2)`; do 
    if [ "$i_outer" == "0" ] && [ "$i_inner" == "$(expr $len - 2)" ]; then
      continue
    fi # special case because the first gets iterated to all and the last connection is implicit
    echo "connection $i_outer (${node_array[$i_outer]}) to $i_inner (${node_array[$i_inner]})"

    #check for intersection
    x1=${lons[$i_outer]}
    y1=${lats[$i_outer]}
    x2=${lons[$i_inner]}
    y2=${lats[$i_inner]}
    # min(a, b) (((a) < (b)) ? (a) : (b))
    min_x=$( echo "scale=19; if ($x1 < $x2) {$x1 + 0.0000001} else {$x2 + 0.0000001}" | bc -l )
    max_x=$( echo "scale=19; if ($x1 > $x2) {$x1 - 0.0000001} else {$x2 - 0.0000001}" | bc -l )
    min_y=$( echo "scale=19; if ($y1 < $y2) {$y1 + 0.0000001} else {$y2 + 0.0000001}" | bc -l )
    max_y=$( echo "scale=19; if ($y1 > $y2) {$y1 - 0.0000001} else {$y2 - 0.0000001}" | bc -l )
#    echo "min: $min_x, x1: $x1, x2: $x2"
    #equation for line Ax+By=C
    A=$( echo "scale=19; $y2 - $y1" | bc -l)
    B=$( echo "scale=19; $x1 - $x2" | bc -l)
    C=$( echo "scale=19; $A * $x1 + $B * $y1" | bc -l)
#    echo "Ax+By=C : $A x + $B y = $C"
    crossing="0"
    for i_segment in `seq 0 $(expr $len_segments - 1)`; do
      #A1 = A, A2 = segments_A[i], B1=B, B2=segments_B[i]
      A1=$A
      A2=${segments_A[$i_segment]}
      B1=$B
      B2=${segments_B[$i_segment]}
      det=$( echo "scale=19; $A1 * $B2 - $A2 * $B1" | bc -l)
#      echo "det$i_segment: $det"
      if [ "$det" == "0" ]; then
        echo "parallell!"
        continue
      fi
      C1=$C
      C2=${segments_C[$i_segment]}
      x=$( echo "scale=19; ( $B2 * $C1 - $B1 * $C2 ) / $det" | bc -l )
      y=$( echo "scale=19; ( $A1 * $C2 - $A2 * $C1 ) / $det" | bc -l )
#      echo "x: $x, y: $y"
#      echo "<node id=\"$i_outer$i_inner$i_segment\" lat=\"$y\" lon=\"$x\" version=\"1\" timestamp=\"2010-12-22T16:09:27Z\" changeset=\"1\" uid=\"1\" user=\"SteveC\"/>" >> debug.osm
      #min(x1,x2) ≤ x ≤ max(x1,x2) 
      if [ "$( echo "scale=19; ($min_x < $x) && ($x < $max_x) && ($min_y < $y) && ($y < $max_y) && (${min_xs[$i_segment]} < $x) && ($x < ${max_xs[$i_segment]}) && (${min_ys[$i_segment]} < $y) && ($y < ${max_ys[$i_segment]})" | bc -l )" == "1" ]; then
        echo "<node id=\"$i_outer$i_inner${i_segment}00\" lat=\"$y\" lon=\"$x\" version=\"1\" timestamp=\"2010-12-22T16:09:27Z\" changeset=\"1\" uid=\"1\" user=\"Me\" />" >> debug.osm
        echo "crossing found!"
        crossing=1
        break
      fi
    done

    if [ "$crossing" == "0" ]; then
      echo "  <way id=\"${wayid}010${i_outer}0${i_inner}\" timestamp=\"2010-12-23T18:48:05Z\" changeset=\"1\" version=\"1\" uid=\"1\" user=\"polytrianguler\">" >> $outfile
      echo "    <nd ref=\"${node_array[$i_outer]}\"/>" >> $outfile
      echo "    <nd ref=\"${node_array[$i_inner]}\"/>" >> $outfile
      echo "    $waytags" >> $outfile
      echo "  </way>" >> $outfile
    fi
  done
done 

echo "</osm>" >> $outfile
echo "</osm>" >> debug.osm
