#!/bin/bash

method="dd"
image="ami-59d6f933"
username="ubuntu"
location=""
device_map="/dev/xvdf"
verbose=false
FILE_SYSTEM_TYPE=ext4
DEFAULT_VOLUME_DIR=/mount_data

verbose() {
  if [[ ! -z $EC2_BACKUP_VERBOSE ]]; then
    echo $@ >&2
  fi
}

Instance_Creation()
{
  if [ -z "$EC2_BACKUP_FLAGS_SSH" ]
  then
    echo "Please set the environment variable EC2_BACKUP_FLAGS_SSH as -i keyname.pem"
    exit 1
  fi

  instance=`eval "aws ec2 run-instances --image-id $image $EC2_BACKUP_FLAGS_AWS --output text --query 'Instances[0].InstanceId'"`
  if [ ! $? -eq 0 ]
  then
    echo "Can not create and run the aws ec2 instance, please check your aws configuration."
    exit 1
  fi
  verbose "New Instance-Id is $instance"
  location=`aws ec2 describe-instances --output text --instance-id $instance|grep PLACEMENT|awk '{print $2}'`
  verbose "location is $location"

  local COUNT=0
  sleep 60
  while [[ `aws ec2 describe-instances --filters "Name=instance-id, Values=$instance" --output text --query "Reservations[0].[Instances[0].State.Code]"` !=  16 ]]; do
    verbose "Waiting for instance state to change to \"running\"."
    sleep 2
    COUNT=`expr $COUNT + 1`
    if [[ $COUNT -gt "30" ]]; then
      print_err "Timeout: creating instance"
      exit 1
    fi
  done
  verbose  "State changed to \"running\""
  aws_hostname=`eval "aws ec2 describe-instances --instance-ids $instance --output text --query 'Reservations[0].Instances[0].PublicIpAddress'"`
  verbose "Public IP address: $aws_hostname"
}

### Usage Function
usage() {
  echo "ec2_backup [-h] [-m method] [-v volume-id] dir "
}

while getopts h:m:v: flag; do
  case "${flag}" in
    h) usage ;;
  m) if [ $OPTARG = "dd" ] || [ $OPTARG = "rsync" ]
  then
    method=$OPTARG
  else
    echo "Please enter correct backup method, either dd or rsync"
    exit 1
  fi ;;
v) if [[ $OPTARG =~ ^vol- ]]
then
  volumeid=$OPTARG
else
  echo "Please enter correct Volume-id, it should start from vol-"
  exit 1
fi ;;
    *) echo "`basename ${0}` [-h usage] | [-m method] | [-v volume-id] directory"
      exit 1
      ;;
  esac
done

shift $(($OPTIND-1))
directory=$1
if [ ! -d "$directory" ]
then
  echo " $directory: No such directory exists"
  exit 1
fi

verbose "Congrulations:You have selected $method method to backup directory $directory"

# compute the size of directory in GB and then assign to Volume
Calculate_Size()
{
  size=$(du -sb $directory|awk '{print $1}')
  new_vol=`expr $size \* 2`
  gb=`expr 1024 \* 1024 \* 1024`
  new_vol_gb=`expr $new_vol / $gb`
  if [ $new_vol_gb -lt 1 ]
  then
    new_vol_gb=1
  else
    new_vol_gb=$new_vol_gb
  fi
}

volume_creation()
{
  new_volumeid=`aws ec2 create-volume --output text --availability-zone $location --size $new_vol_gb --volume-type gp2|awk '{print $7}'` >/dev/null
  if [ ! $? -eq 0 ]
  then
    echo "Can not create and the aws ec2 volume, please check your aws configuration."
    exit 1
  fi
  verbose "Attached new volume_id is $new_volumeid"
  volumeid="$new_volumeid"
  sleep 10
}

Volume_Attach()
{
  aws ec2 attach-volume --volume-id $volumeid --instance-id $instance --device $device_map > /dev/null
  sleep 05
  volsize=`aws ec2 describe-volumes --output text --volume-ids $volumeid|grep VOLUMES|awk '{print $5}'`
  verbose "New volume $volumeid of size $volsize GB has been attached to $instance"
  volstatus=`aws ec2 describe-volumes --output text --volume-ids $volumeid|grep ATTACHMENTS|awk '{print $6}'`
  ssh -o StrictHostKeyChecking=no -o BatchMode=yes $EC2_BACKUP_FLAGS_SSH ubuntu@$aws_hostname sudo mkfs -t ext4 $device_map >/dev/null
  if [ ! $? -eq 0 ]
  then
    echo "Can not create the file system on the temporary ec2 instance."
    echo "Please check if the environment variable \$EC2_BACKUP_FLAGS_SSH is set and the security group has access to the TCP port 22 on the instance."
    Terminate_Instance
    exit 1
  fi
  ssh -o StrictHostKeyChecking=no $EC2_BACKUP_FLAGS_SSH ubuntu@$aws_hostname sudo mkdir /mount_data > /dev/null
  if [ ! $? -eq 0 ]
  then
    echo "Can not create the file system on the temporary ec2 instance."
    echo "Please check if the environment variable \$EC2_BACKUP_FLAGS_SSH is set and the security group has access to the TCP port 22 on the instance."
    Terminate_Instance
    exit 1
  fi
  ssh -o StrictHostKeyChecking=no $EC2_BACKUP_FLAGS_SSH ubuntu@$aws_hostname sudo mount $device_map /mount_data > /dev/null
  if [ ! $? -eq 0 ]
  then
    echo "Can not create the file system on the temporary ec2 instance."
    echo "Please check if the environment variable \$EC2_BACKUP_FLAGS_SSH is set and the security group has access to the TCP port 22 on the instance."
    Terminate_Instance
    exit 1
  fi
}

Volume_Detach()
{
  ssh -o StrictHostKeyChecking=no ${EC2_BACKUP_FLAGS_SSH} ubuntu@$aws_hostname sudo umount /mount_data
  aws ec2 detach-volume --volume-id $volumeid --output text >/dev/null
  if [ ! $? -eq 0 ]
  then
    echo "Can not detach the volume."
    exit 1
  fi
  verbose "VOLUME $volumeid HAS BEEN DETACHED"
}

Terminate_Instance()
{
  aws ec2 terminate-instances --instance-ids $instance >/dev/null
  if [ ! $? -eq 0 ]
  then
    echo "Can not terminate the instance."
    exit 1
  fi
  verbose "INSTANCE $instance HAS BEEN TERMINATED"
}

rsync()
{
  if [ $method = "rsync" ]
  then
    verbose "PERFORMING BACKUP OF DIRECTORY $directory WITH $method"
    rsync -e \"ssh ${EC2_BACKUP_FLAGS_SSH}\" --rsync-path=\"sudo rsync\" -avpzh $directory $username@$aws_hostname:/mount_data > /dev/null
  else
    verbose "PERFORMING BACKUP OF DIRECTORY $directory WITH $method"
    dd
  fi
}

dd_backup() {
  verbose "Backing up by 'dd'"
  tar -cPf - $directory | ssh ${EC2_BACKUP_FLAGS_SSH} -o BatchMode=yes -o StrictHostKeyChecking=no $username@$aws_hostname 'sudo dd of=/mount_data/backup.tar' >/dev/null 2>&1
  verbose "Successfully backed up"
}

Instance_Creation
Calculate_Size
if [ ! -z "$volumeid" ]
then
  volsize=`aws ec2 describe-volumes --output text --volume-ids $volumeid|grep VOLUMES|awk '{print $5}'`
  verbose "Volume size: $volsize GB"
  volstatus=`aws ec2 describe-volumes --output text --volume-ids $volumeid|grep VOLUMES|awk '{print $7}'`
  verbose "Volume status: $volstatus status"
  vollocation=`aws ec2 describe-volumes --output text --volume-ids $volumeid|grep VOLUMES|awk '{print $2}'`
  if [ $vollocation != "us-east-1d" ]
  then
    echo "Specified volume location should be from us-east-1d zone, but it belongs to $vollocation"
    Terminate_Instance
    exit 1
  fi
  if [ $volstatus = "in-use" ]
  then
    echo "Currently $volumeid is in-use so cannot me used for backup"
    Terminate_Instance
    exit 1
  fi
  if [ $volsize -lt $new_vol_gb ]
  then
    echo "Specified volume should have at least $new_vol_gb space"
    Terminate_Instance
    exit 1
  fi
  Volume_Attach
else
  volume_creation
  Volume_Attach
fi

if [ $method = "dd" ]
then
  dd_backup
  Volume_Detach
  Terminate_Instance
  echo $volumeid
else
  rsync
  Volume_Detach
  Terminate_Instance
  echo $volumeid
fi
