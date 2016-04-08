#!/bin/bash
Instance_Creation()
{
image="ami-fce3c696"
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

#if [ -z  $keypair ] || [  -z $secgroup  ]; then
       # echo "The keypair or the security group are empty please set them in EC2_BACKUP_FLAGS_AWS" 1>&2
       # exit 1
#fi

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
}

### Usage Function
usage() {
echo "ec2_backup [-h] [-m method] [-v volume-id] dir "
}
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

# compute the size of directory in GB and then assign to Volume

Calculate_Size()
{
size=$(du -sb $directory|awk '{print $1}')
new_vol=`expr $size \* 2`
gb=`expr 1024 \* 1024 \* 1024`
new_vol_gb=`expr $new_vol / $gb`
echo $new_vol_gb
if [ $new_vol_gb -lt 1 ]
then
new_vol_gb=1
else
new_vol_gb= $new_vol_gb
fi
}

Volume_Attach()
{
new_volume_id=`aws ec2 create-volume --output text --availability-zone $location --size $new_vol_gb|awk '{print $6}'` >/dev/null
sleep 10
aws ec2 attach-volume --volume-id $new_volume_id --instance-id $instance --device $device_map > /dev/null
echo $new_volume_id
sleep 05
volsize=`aws ec2 describe-volumes --output text --volume-ids $new_volume_id|awk '{print $4}'`
echo "The size is: $volsize"
volstatus=`aws ec2 describe-volumes --output text --volume-ids $new_volume_id|awk '{print $6}'`
echo "The Status is : $volstatus"
ssh -o StrictHostKeyChecking=no ${EC2_BACKUP_FLAGS_SSH} ubuntu@$aws_hostname sudo mkfs -t ext4 $device_map > /dev/null
ssh -o StrictHostKeyChecking=no ${EC2_BACKUP_FLAGS_SSH} ubuntu@$aws_hostname sudo mkdir /mount_data > /dev/null
ssh -o StrictHostKeyChecking=no ${EC2_BACKUP_FLAGS_SSH} ubuntu@$aws_hostname sudo mount $device_map /mount_data > /dev/null
}

Volume_Detach()
{
ssh -o StrictHostKeyChecking=no ${EC2_BACKUP_FLAGS_SSH} ubuntu@$aws_hostname sudo umount /mount_data
aws ec2 detach-volume --volume-id $new_volume_id --output text >/dev/null
echo "Volume $new_volume_id has been detached"
}
Terminate_Instance()
{
aws ec2 terminate-instances --instance-ids $instance >/dev/null
echo "Instance Terminated"
}


rsync()
{
if [ $method = "rsync" ]
then
echo $1
`rsync -ravh --rsync-path="sudo rsync" -e "ssh $EC2_BACKUP_FLAGS_SSH -o StrictHostKeyChecking=no" $1 $ubuntu@aws_hostname:/mount_data` > /dev/null
else
 dd
fi
}

dd()
{
echo $method
}
