#!/bin/bash

## HiC-Pro           
## Copyleft 2015-2016 Institut Curie
## Author(s): Alex Barrera, Nicolas Servant
## Contact: nicolas.servant@curie.fr
## This software is distributed without any guarantee under the terms of the GNU General
## Public License, either Version 2, June 1991 or Version 3, June 2007.

##
## First version of converter between HiCPro and juicebox. Note tht it does not seem that juicebox 1.4 was able to deal with Dnase Hi-C data.
## The current script should but '0' if no restriction fragments are available, but juicebox does not recognize it

function usage {
    echo -e "usage : hicpro2juicebox -i VALIDPAIRS -g GSIZE -j JUICERJAR [-r RESFRAG] [-t TEMP] [-o OUT] [-h]"
    echo -e "Use option -h|--help for more information"
}

function help {
    usage;
    echo 
    echo "Generate JuiceBox input file from HiC-Pro results"
    echo "See http://www.aidenlab.org/juicebox/ for details about Juicebox"
    echo "---------------"
    echo "OPTIONS"
    echo
    echo "   -i|--input VALIDPAIRS : allValidPairs file generated by HiC-Pro >= 2.7.5"
    echo "   -g|--gsize GSIZE : genome size file used during HiC-Pro processing"
    echo "   -j|--jar JUICERJAR : path to juicebox_clt.jar file"
    echo "   [-r|--resfrag] RESFRAG : restriction fragment file used by HiC-Pro"
    echo "   [-t|--temp] TEMP : path to tmp folder. Default is current path"
    echo "   [-o|--out] OUT : output path. Default is current path"
    echo "   [-h|--help]: help"
    exit;
}


if [ $# -lt 1 ]
then
    usage
    exit
fi

# Transform long options to short ones
for arg in "$@"; do
  shift
  case "$arg" in
      "--input") set -- "$@" "-i" ;;
      "--genome")   set -- "$@" "-g" ;;
      "--jar")   set -- "$@" "-j" ;;
      "--resfrag") set -- "$@" "-r" ;;
      "--temp")   set -- "$@" "-t" ;;
      "--out")   set -- "$@" "-o" ;;
      "--help")   set -- "$@" "-h" ;;
       *)        set -- "$@" "$arg"
  esac
done

VALIDPAIRS=""
RESFRAG=""
GSIZE=""
JUICERJAR=""
TEMP="./tmp"
OUT="./"

while getopts ":i:r:g:j:t:o:ch" OPT
do
    case $OPT in
	i) VALIDPAIRS=$OPTARG;;
	g) GSIZE=$OPTARG;;
	j) JUICERJAR=$OPTARG;;
	r) RESFRAG=$OPTARG;;
	t) TEMP=$OPTARG;;
	o) OUT=$OPTARG;;
	h) help ;;
	\?)
	    echo "Invalid option: -$OPTARG" >&2
	    usage
	    exit 1
	    ;;
	:)
	    echo "Option -$OPTARG requires an argument." >&2
	    usage
	    exit 1
	    ;;
    esac
done

if [[ -z $VALIDPAIRS || -z $GSIZE || -z $JUICERJAR ]]; then
    usage
    exit
fi

## Create output folder
mkdir -p ${TEMP}

## Check JAVA version
JAVA_VERSION=$(java -version 2>&1 |awk 'NR==1{ gsub(/"/,""); print $3 }')
if [[ "$JAVA_VERSION" < "1.8" ]]; then
    echo "Warning : Java version must be > 1.8.0 to use Juicebox - $JAVA_VERSION detected"
fi

if [[ ! -e $JUICERJAR ]]; then
    echo "Juicebox .jar file not found. Exit"
    exit 1
fi

## Deal with old format
nbfields=$(head -1 $VALIDPAIRS | awk '{print NF}')

if [[ $nbfields == "12" ]]; then
    echo -e "HiC-Pro format > 2.7.5 detected ..."

elif [[ $nbfields == "8" ]]; then
    echo -e "HiC-Pro format < 2.7.6 detected ..."
    echo -e "Adjusting AllValidPairs format ..."
    awk '{OFS="\t"; print $0,0,1,42,42}' $VALIDPAIRS > ${TEMP}/$$_format_AllValidPairs
    VALIDPAIRS=${TEMP}/$$_format_AllValidPairs

else
    echo -e "Error : unknown format - $nbfields detected, whereas 8 (< v2.7.6) or 12 (> v2.7.5) fields are expected !"
    exit 1
fi

echo "Generating Juicebox input files ..."

if [[ ! -z $RESFRAG ]]; then
 
    ## The restriction fragment sites file needs to be converted in order to be used in Juicebox command line tool (see attached script). 
    ## They expect one line per chromosome with restriction sites separated by tabs and sorted by coordinate.
    ## Fix bug reported
    awk 'BEGIN{OFS="\t"; prev_chr=""}$1!=prev{print ""; prev=$1; printf "%s\t", $1} $1==prev {printf "%s\t",$3+1} END{print ""}' $RESFRAG | sed "s/\t\n/\n/" | sed "/^$/d" > ${TEMP}/$$_resfrag.juicebox
    ##awk 'BEGIN{OFS="\t"; prev_chr=""}$1!=prev{print ""; prev=$1; printf "%s\t", $1; printf "%s\t", $3} $1==prev{printf "%s\t",$3}END{print ""}' $RESFRAG | sed "s/\t\n/\n/" | sed "/^$/d" > ${TEMP}/$$_resfrag.juicebox

    ## The “pre” command needs the contact map to be sorted by chromosome and grouped so that all reads for one chromosome (let’s say, chr1) appear in the same column.
    ## Also, chromosomes should not have the ‘chr” substring and the strand is coded as 0 for positive and anything else for negative (in practice, 1).
    awk '{$4=$4!="+"; $7=$7!="+"; n1=split($9, frag1, "_"); n2=split($10, frag2, "_"); } $2<=$5{print $1, $4, $2, $3, frag1[n1], $7, $5, $6, frag2[n2], $11, $12 }$5<$2{ print $1, $7, $5, $6, frag2[n2], $4, $2, $3, frag1[n1], $12, $11}' $VALIDPAIRS | sort -T ${TEMP} -k3,3d -k7,7d -S 90% > ${TEMP}/$$_allValidPairs.pre_juicebox_sorted
else
    awk '{$4=$4!="+"; $7=$7!="+"} $2<=$5{print $1, $4, $2, $3, 0, $7, $5, $6, 1, $11, $12 }$5<$2{ print $1, $7, $5, $6, 0, $4, $2, $3, 1, $12, $11 }' $VALIDPAIRS | sort -T ${TEMP} -k3,3d  -k7,7d -S 90% > ${TEMP}/$$_allValidPairs.pre_juicebox_sorted
fi

echo -e "Running Juicebox ..."
OUTPUTFILE=${OUT}/$(basename $VALIDPAIRS).hic

## This is the command to generate the hic file that can be visualized with Juicebox with restriction fragment information

if [[ ! -z $RESFRAG ]]; then
    java -jar ${JUICERJAR} pre -f ${TEMP}/$$_resfrag.juicebox ${TEMP}/$$_allValidPairs.pre_juicebox_sorted ${OUTPUTFILE} ${GSIZE}
else
    java -jar ${JUICERJAR} pre ${TEMP}/$$_allValidPairs.pre_juicebox_sorted ${OUTPUTFILE} ${GSIZE}
fi

## Clean
/bin/rm -f ${TEMP}/$$_resfrag.juicebox ${TEMP}/$$_allValidPairs.pre_juicebox_sorted

echo "done !"
