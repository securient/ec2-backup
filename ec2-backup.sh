#!/bin/bash
Instance_Creation()
{
image="ami-fce3c696"
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
   echo "Please set the environment variable EC2_BACKUP_FLAGS_SSH as -i keyname.pem"
  exit 1
fi

#if [ -z  $keypair ] || [  -z $secgroup  ]; then
       # echo "The keypair or the security group are empty please set them in EC2_BACKUP_FLAGS_AWS" 1>&2
       # exit 1
#fi

instance=`aws ec2 run-instances --image-id ami-fce3c696 --instance-type t2.micro --key-name keyname --security-groups SN_2|grep INSTANCES|awk '{print $8}'`
if [ $EC2_BACKUP_FLAGS_VERBOSE = "true" ]
then
echo "New Instance-Id is $instance"
fi
location=`aws ec2 describe-instances --output text --instance-id $instance|grep PLACEMENT|awk '{print $2}'`
if [ $EC2_BACKUP_FLAGS_VERBOSE = "true" ]
then
echo "location is $location"
fi
sleep 60
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
       echo "Please enter correct Volume-id"
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
                echo " $directory:No such directory exists"
                exit 1
fi

echo $directory
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

Volume_Attach()
{
new_volumeid=`aws ec2 create-volume --output text --availability-zone $location --size $new_vol_gb --volume-type gp2|awk '{print $7}'` >/dev/null
sleep 10
echo "The new attached volume is $new_volumeid"
aws ec2 attach-volume --volume-id $new_volumeid --instance-id $instance --device $device_map > /dev/null
sleep 05
volsize=`aws ec2 describe-volumes --output text --volume-ids $new_volumeid|grep VOLUMES|awk '{print $5}'`
echo "Attached volume size is: $volsize"
volstatus=`aws ec2 describe-volumes --output text --volume-ids $new_volumeid|grep ATTACHMENTS|awk '{print $6}'`
echo "Attached volume status is : $volstatus"
echo "The directory is $directory"
ssh -o StrictHostKeyChecking=no ${EC2_BACKUP_FLAGS_SSH} ubuntu@$aws_hostname sudo mkfs -t ext4 $device_map >/dev/null
ssh -o StrictHostKeyChecking=no ${EC2_BACKUP_FLAGS_SSH} ubuntu@$aws_hostname sudo mkdir /mount_data > /dev/null
ssh -o StrictHostKeyChecking=no ${EC2_BACKUP_FLAGS_SSH} ubuntu@$aws_hostname sudo mount $device_map /mount_data > /dev/null
echo "Mounting is created"
#`rsync -ravh --rsync-path="sudo rsync" -e "ssh $EC2_BACKUP_FLAGS_SSH -o StrictHostKeyChecking=no" $directory $ubuntu@aws_hostname:/mount_data` > /dev/null
}

Volume_Detach()
{
ssh -o StrictHostKeyChecking=no ${EC2_BACKUP_FLAGS_SSH} ubuntu@$aws_hostname sudo umount /mount_data
aws ec2 detach-volume --volume-id $volumeid --output text >/dev/null
echo "Volume $volumeid has been detached"
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
rsyncstatus=`rsync -ravv --rsync-path="sudo rsync" -e "ssh $EC2_BACKUP_FLAGS_SSH -o StrictHostKeyChecking=no" --delete $directory $ubuntu@aws_hostname:/mount_data 2>&1`
#echo `rsync -ravh --rsync-path="sudo rsync" -e "ssh $EC2_BACKUP_FLAGS_SSH -o StrictHostKeyChecking=no" $directory $ubuntu@aws_hostname:/mount_data` > /dev/null
else
dd
fi
}

dd()
{
if [ $method = "dd" ]
then
echo "Entered"
var=`tar -Pcf - $directory | ssh \${EC2_BACKUP_FLAGS_SSH} -o StrictHostKeyChecking=no ubuntu@$aws_hostname 'sudo dd of=/dev/xvdf'`
echo $var
echo "dd Finished"
fi
}

Instance_Creation
Calculate_Size
echo $volumeid
if [ ! -z "$volumeid" ]
    then
         volsize=`aws ec2 describe-volumes --output text --volume-ids $volumeid|grep VOLUMES|awk '{print $5}'`
         echo $volsize
         volstatus=`aws ec2 describe-volumes --output text --volume-ids $volumeid|grep VOLUMES|awk '{print $7}'`
          echo $volstatus
          if [ $volstatus = "in-use" ]
          then
          echo "Currently $volumeid is in-use so cannot me used for backup"
          exit 1
          fi
         if [ $volsize -lt $new_vol_gb ]
         then
         echo "Specified volume should have atleast $new_vol_gb space"
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
          echo "dd Function"
          echo "Volume_Detach"
          echo "Terminate_Instance"
          echo $new_volumeid
        else
          echo "rsync Function"
          echo "Volume_Detach"
          echo "Terminate_Instance"
          echo $new_volumeid
     fi
fi
