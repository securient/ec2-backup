#!/bin/bash
Instance_Creation()
{
image="ami-fce3c696"
method="dd"
default_map=""
username="ubuntu"
location=""
device_map="/dev/xvdf"
verbose_flag="False"
if [ ! -z "$EC2_BACKUP_FLAGS_VERBOSE" ]
  then
                verbose_flag=$EC2_BACKUP_FLAGS_VERBOSE
fi
  echo $verbose_flag

if [ -z "$EC2_BACKUP_FLAGS_SSH" ]
  then
   echo "Environment variable is not set: $EC2_BACKUP_FLAGS_SSH"
  exit 1
fi

instance=`aws ec2 run-instances --image-id ami-fce3c696 --instance-type t2.micro --key-name keyname --security-groups SN_2|grep INSTANCES|awk '{print $8}'`
echo "New Instance-Id is $instance"
location=`aws ec2 describe-instances --output text --instance-id $instance|grep PLACEMENT|awk '{print $2}'`
echo "location is $location"
default_map=`aws ec2 describe-instances --output text --instance-id $instance|grep BLOCKDEVICEMAPPINGS|awk '{print $2}'`
echo "$instance is mapped to $default_map"
sleep 50
state=`aws ec2 describe-instances --output text --instance-id $instance|grep -i State|awk '{print $3}'`
echo $state
state=`aws ec2 describe-instances --output text --instance-id $instance|grep -i State|awk '{print $3}'`
echo $state

aws_hostname=`aws ec2 describe-instances --instance-ids $instance|grep ASSOCIATION|awk '{print $3}'|awk 'NR==1'`
echo $aws_hostname
echo "ssh -o StrictHostKeyChecking=no ${EC2_BACKUP_FLAGS_SSH} ubuntu@$aws_hostname"
ssh -o StrictHostKeyChecking=no ${EC2_BACKUP_FLAGS_SSH} ubuntu@$aws_hostname
}

usage() {
echo "ec2_backup [-h] [-m method] [-v volume-id] dir "
}
# Parameter selection based on parameter
while getopts h:m:v: flag; do
  case "${flag}" in
   h) usage ;;
   m) if [ $OPTARG = "dd" ] || [ $OPTARG = "rsync" ]; then
          method=$OPTARG
      else
          echo "Please enter correct method, either dd or rsync"
          exit 1
      fi ;;
   v) volumeid=$OPTARG;;
    *) echo "`basename ${0}` [-h usage] | [-m method] | [-v volume-id] directory"
           exit 1
           ;;
  esac
done

shift $(($OPTIND-1))
directory=$1
if [ ! -d "$directory" ]
        then
                echo " $directory:No such directory exists"
                exit 1
fi

#To compute the size of directory and assign to directory
#Calculate_Size()
#{
#size= du -sb $directory | awk '{print $1}' #generates size in bytes
#new_vol= size * 2
#}

usage
Instance_Creation
Terminate_Instance
