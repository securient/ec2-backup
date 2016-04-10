#!/bin/bash

method="dd"
image="ami-59d6f933"
username="ubuntu"
location=""
device_map="/dev/xvdf"
verbose=false

if [ ! -z "$EC2_BACKUP_VERBOSE" ]
then
  verbose=true
fi

Instance_Creation()
{
  if [ -z "$EC2_BACKUP_FLAGS_SSH" ]
  then
    echo "Please set the environment variable EC2_BACKUP_FLAGS_SSH as -i keyname.pem"
    exit 1
  fi

  #if [ -z  $keypair ] || [  -z $secgroup  ]; then
  # echo "The keypair or the security group are empty please set them in EC2_BACKUP_FLAGS_AWS" 1>&2
  # exit 1
  #fi

  instance=`eval "aws ec2 run-instances --image-id $image $EC2_BACKUP_FLAGS_AWS --output text --query 'Instances[0].InstanceId'"`
  if [ "$verbose" = true ]
  then
    echo "New Instance-Id is $instance"
  fi
  location=`aws ec2 describe-instances --output text --instance-id $instance|grep PLACEMENT|awk '{print $2}'`
  if [ "$verbose" = true ]
  then
    echo "location is $location"
  fi

  local COUNT=0
  sleep 60
  while [[ `aws ec2 describe-instances --filters "Name=instance-id, Values=$instance" --output text --query "Reservations[0].[Instances[0].State.Code]"` !=  16 ]]; do

    if [ "$verbose" = true ]
    then
      echo "Waiting for instance state to change to \"running\"."
    fi
    sleep 2
    COUNT=`expr $COUNT + 1`
    if [[ $COUNT -gt "30" ]]; then
      print_err "Timeout: creating instance"
      exit 1
    fi
  done
  if [ "$verbose" = true ]
  then
    echo "State changed to \"running\""
  fi
  aws_hostname=`eval "aws ec2 describe-instances --instance-ids $instance --output text --query 'Reservations[0].Instances[0].PublicIpAddress'"`
  if [ "$verbose" = true ]
  then
    echo "Public IP address: $aws_hostname"
  fi
  if [ "$verbose" = true ]
  then
    echo $aws_hostname
    echo "ssh -o StrictHostKeyChecking=no ${EC2_BACKUP_FLAGS_SSH} ubuntu@$aws_hostname"
  fi
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

if [ "$verbose" = true ]
then
  echo "Congrulations:You have selected $method method to backup directory $directory"
fi

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

FILE_SYSTEM_TYPE=ext4
DEFAULT_VOLUME_DIR=/mount_data

Volume_Attach()
{
  new_volumeid=`aws ec2 create-volume --output text --availability-zone $location --size $new_vol_gb --volume-type gp2|awk '{print $7}'` >/dev/null
  sleep 10
  if [ "$verbose" = true ]
  then
    echo "Attached new volume_id is $new_volumeid"
  fi
  aws ec2 attach-volume --volume-id $new_volumeid --instance-id $instance --device $device_map > /dev/null
  sleep 05
  volsize=`aws ec2 describe-volumes --output text --volume-ids $new_volumeid|grep VOLUMES|awk '{print $5}'`
  if [ "$verbose" = true ]
  then
    echo "New volume $new_volumeid of size $volsize GB has been attached to $instance"
  fi
  volstatus=`aws ec2 describe-volumes --output text --volume-ids $new_volumeid|grep ATTACHMENTS|awk '{print $6}'`
  # echo "ssh $EC2_BACKUP_FLAGS_SSH $username@$aws_hostname -o BatchMode=yes -o StrictHostKeyChecking=no \"sudo mkfs -t ext4 $device_map\""
  # `eval "ssh $EC2_BACKUP_FLAGS_SSH $username@$aws_hostname -o BatchMode=yes -o StrictHostKeyChecking=no \"sudo mkdir /mount_data\""`
  # `eval "ssh $EC2_BACKUP_FLAGS_SSH $username@$aws_hostname -o BatchMode=yes -o StrictHostKeyChecking=no \"sudo mount $device_map /mount_data\""`
  ssh -o StrictHostKeyChecking=no -o BatchMode=yes $EC2_BACKUP_FLAGS_SSH ubuntu@$aws_hostname sudo mkfs -t ext4 $device_map >/dev/null
  ssh -o StrictHostKeyChecking=no $EC2_BACKUP_FLAGS_SSH ubuntu@$aws_hostname sudo mkdir /mount_data > /dev/null
  ssh -o StrictHostKeyChecking=no $EC2_BACKUP_FLAGS_SSH ubuntu@$aws_hostname sudo mount $device_map /mount_data > /dev/null
  #`rsync -ravh --rsync-path="sudo rsync" -e "ssh $EC2_BACKUP_FLAGS_SSH -o StrictHostKeyChecking=no" $directory $ubuntu@aws_hostname:/mount_data` > /dev/null
}

Volume_Detach()
{
  ssh -o StrictHostKeyChecking=no ${EC2_BACKUP_FLAGS_SSH} ubuntu@$aws_hostname sudo umount /mount_data
  aws ec2 detach-volume --volume-id $volumeid --output text >/dev/null
  if [ "$verbose" = true ]
  then
    echo "VOLUME $volumeid HAS BEEN DETACHED"
  fi
}

Terminate_Instance()
{
  aws ec2 terminate-instances --instance-ids $instance >/dev/null
  if [ "$verbose" = true ]
  then
    echo "INSTANCE $instance HAS BEEN TERMINATED"
  fi
}

rsync()
{
  if [ $method = "rsync" ]
  then
    if [ "$verbose" = true ]
    then
      echo "PERFORMING BACKUP OF DIRECTORY $directory WITH $method"
    fi
    echo "rsync -e \"ssh ${EC2_BACKUP_FLAGS_SSH}\" --rsync-path=\"sudo rsync\" -avpzh $directory $username@$aws_hostname:/mount_data"
    rsync -e \"ssh ${EC2_BACKUP_FLAGS_SSH}\" --rsync-path=\"sudo rsync\" -avpzh $directory $username@$aws_hostname:/mount_data > /dev/null
  else
    if [ "$verbose" = true ]
    then
      echo "PERFORMING BACKUP OF DIRECTORY $directory WITH $method"
    fi
    dd
  fi
}

dd_backup() {
    echo "Backing up by 'dd'"
    tar -cPf - $directory | ssh ${EC2_BACKUP_FLAGS_SSH} -o BatchMode=yes -o StrictHostKeyChecking=no $username@$aws_hostname 'sudo dd of=/mount_data/backup.tar'
    echo "Successfully backed up"
}

Instance_Creation
Calculate_Size
echo $volumeid
if [ ! -z "$volumeid" ]
then
  volsize=`aws ec2 describe-volumes --output text --volume-ids $volumeid|grep VOLUMES|awk '{print $5}'`
  if [ "$verbose" = true ]
  then
    echo $volsize
  fi
  volstatus=`aws ec2 describe-volumes --output text --volume-ids $volumeid|grep VOLUMES|awk '{print $7}'`
  if [ "$verbose" = true ]
  then
    echo $volstatus
  fi
  vollocation=`aws ec2 describe-volumes --output text --volume-ids vol-6c6e99bd|grep VOLUMES|awk '{print $2}'`
  if [ $vollocation != "us-east-1d" ]
  then
    echo "Specified volume location should be from us-east-1d zone, but it belongs to $vollocation"
    exit 1
  fi
  if [ $volstatus = "in-use" ]
  then
    echo "Currently $volumeid is in-use so cannot me used for backup"
    exit 1
  fi
  if [ $volsize -lt $new_vol_gb ]
  then
    echo "Specified volume should have atleast $new_vol_gb space"
    exit 1
  else
    aws ec2 attach-volume --volume-id $volumeid --instance-id $instance --device $device_map > /dev/null
    sleep 10
    ssh -o StrictHostKeyChecking=no ${EC2_BACKUP_FLAGS_SSH} ubuntu@$aws_hostname sudo mkfs -t ext4 $device_map >/dev/null
    ssh -o StrictHostKeyChecking=no ${EC2_BACKUP_FLAGS_SSH} ubuntu@$aws_hostname sudo mkdir /mount_data > /dev/null
    ssh -o StrictHostKeyChecking=no ${EC2_BACKUP_FLAGS_SSH} ubuntu@$aws_hostname sudo mount $device_map /mount_data > /dev/null

    if [ $method = "dd" ]
    then
      echo "dd Function"
      echo "Volume_Detach"
      echo "Terminate_Instance"
      echo $volumeid
    else
      echo "rsync"
      echo "Volume_Detach"
      echo "Terminate_Instance"
      echo $volumeid
    fi
  fi
else
  Volume_Attach
  if [ $method = "dd" ]
  then
    dd_backup
    echo "Volume_Detach"
    echo "Terminate_Instance"
    echo $new_volumeid
  else
    rsync
    echo "rsync Function"
    echo "Volume_Detach"
    echo "Terminate_Instance"
    echo $new_volumeid
  fi
fi
