#!/bin/sh
Instance_Creation()
{
image="ami-fce3c696"
method="dd"
username="ubuntu"
location=""
device_map=""
#echo "aws ec2 run-instances  $ec2defaults"
#if [ -z  $keypair ] || [  -z $secgroup  ]; then
       # echo "The keypair or the security group are empty please set them in EC2_BACKUP_FLAGS_AWS" 1>&2
       # exit 1
#fi
instance=`aws ec2 run-instances --image-id ami-fce3c696 --instance-type t2.micro --key-name keyname --security-groups SN_2|grep INSTANCES|awk '{print $8}'`
echo "New Instance-Id is $instance"
location=`aws ec2 describe-instances --output text --instance-id $instance|grep PLACEMENT|awk '{print $2}'`
echo "location is $location"
device_map=`aws ec2 describe-instances --output text --instance-id $instance|grep BLOCKDEVICEMAPPINGS|awk '{print $2}'`
echo "$instance is mapped to $device_map"
sleep 50
state=`aws ec2 describe-instances --output text --instance-id $instance|grep -i State|awk '{print $3}'`
echo $state
state=`aws ec2 describe-instances --output text --instance-id $instance|grep -i State|awk '{print $3}'`
echo $state

aws_hostname=`aws ec2 describe-instances --instance-ids $instance|grep ASSOCIATION|awk '{print $3}'|awk 'NR==1'`
echo $aws_hostname
echo "ssh -i "/home/bpandey/keyname.pem" ubuntu@$aws_hostname -o StrictHostKeyChecking=no"
connect=`ssh -i "/home/bpandey/keyname.pem" ubuntu@$aws_hostname -o StrictHostKeyChecking=no`
# getInstanceStatus() {
#instanceState=`aws ec2 describe-instances --output text --instance-id i-9ecae11d | grep STATE| awk '{print $3}'`
#
 #       if [ "$instanceState" != "pending" ] && [ "$instanceState" != "running" ]; then
  #              echo " Instance is in an unusable state" 1>&2
#               errorTerminate
 #               exit 1;
  #      fi
#}
}
usage() {
echo "ec2_backup [-h] [-m method] [-v volume-id] dir "
}
usage
