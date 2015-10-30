#!/usr/bin/env bash
set -u
LC_ALL=POSIX
usage="$(basename "$0") [-s SECONDS] [-m MINUTES] [-h HOURS] [-d DAYS]"
usage+=" [-p GREP_PATTERN] [-D] [DATASET]\n"
usage+="   All arguments are optional, but you must provide, at least, one of:"
usage+=" -s -m -h -d\n"
usage+="   DATASET limits the snapshots analysis to it\n" 
usage+="   -s delete snapshots older than SECONDS\n"
usage+="   -m delete snapshots older than MINUTES\n"
usage+="   -h delete snapshots older than HOURS\n"
usage+="   -d delete snapshots older than DAYS\n"
usage+="   -p the grep pattern to use\n"
usage+="   -D destroy the snapshots not just print them"

days=0
hours=0
minutes=0
seconds=0
pattern=".*"
test_run=true
dataset=""

while getopts ":Ds:m:h:d:p:" opt; do
  case $opt in
    s)
      seconds=$OPTARG
      ;;
    m)    
      minutes=$OPTARG
      ;;
    h)
      hours=$OPTARG
      ;;
    d)
      days=$OPTARG
      ;;
    p)
      pattern=$OPTARG
      ;;
    D)
      test_run=false
      ;;
    \?)
      echo "Invalid option: -$OPTARG" 1>&2
      echo -e "$usage" 1>&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." 1>&2
      echo -e "$usage" 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))
if (($# != 0)); then
  dataset="$1"
fi

# Figure out which platform we are running on, more specifically, which version
# of date we are using. GNU date behaves different than date on OSX and FreeBSD
platform='unknown'
unamestr=$(uname)

if [[ "$unamestr" == 'Linux' ]]; then
  platform='linux'
elif [[ "$unamestr" == 'FreeBSD' ]]; then
  platform='bsd'
elif [[ "$unamestr" == 'OpenBSD' ]]; then
  platform='bsd'
elif [[ "$unamestr" == 'Darwin' ]]; then
  platform='bsd'
else
  echo -e "unknown platform $unamestr 1>&2"
  exit 1
fi

compare_seconds=$((24*60*60*$days + 60*60*$hours + 60*$minutes + $seconds))
if ((compare_seconds < 1)); then
  echo -e "time has to be in the past" 1>&2
  echo -e "$usage" 1>&2
  exit 1
fi

if [[ "$platform" == 'linux' ]]; then
  compare_timestamp=$(date --date="-$(echo $compare_seconds) seconds" +"%s")
else
  compare_timestamp=$(date -j -v-$(echo $compare_seconds)S +"%s")
fi

# get a list of snapshots sorted by creation date, so that we get the oldest
# first. This will allow us to skip the loop early
cmd="zfs list -r -H -t snapshot -o name,creation -s creation $dataset"
snapshots=$($cmd | grep "$pattern")
if [[ -z $snapshots ]]; then
  echo "no snapshots found!"
  exit 2
fi

# for in uses \n as a delimiter
old_ifs=$IFS
IFS=$'\n'
cnt=0
for line in $snapshots; do
  snapshot=$(echo $line | cut -f 1)
  creation_date=$(echo $line | cut -f 2)

  if [[ "$platform" == 'linux' ]]; then 
    creation_date_timestamp=$(date --date="$creation_date" "+%s")
  else
    creation_date_timestamp=$(date -j -f "%a %b %d %H:%M %Y"\
      "$creation_date" "+%s")
  fi

  # Check if the creation date of a snapshot is less than our compare date
  # Meaning if it is older than our compare date
  # It is younger, we can stop processing since we the list is sorted by
  # compare date '-s creation'
  if ((creation_date_timestamp < compare_timestamp)); then
    if [[ $test_run  == false ]]; then
      echo "DELETE: $snapshot from $creation_date"
      zfs destroy $snapshot
    else
      echo "WOULD DELETE: $snapshot from $creation_date"
    fi
    ((cnt++))
  else
    echo "KEEP: $snapshot from $creation_date"
    echo "No more snapshots to be processed. Skipping.."
    break
  fi
done
if ((cnt == 1)); then
  echo "Processed 1 snapshot"
else
  echo "Processed $cnt snapshots"
fi
IFS=$old_ifs
if ((cnt == 0)); then
  exit 2
fi
exit 0
set +u
