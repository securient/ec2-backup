# ec2-backup

Teammates: [Bipin Pandey](https://github.com/securient/ec2-backup/commits/master?author=Bipin007), [Vinod Tiwari](https://github.com/securient/ec2-backup/commits/master?author=securient), [Peixuan Ding](https://github.com/securient/ec2-backup/commits/master?author=dinever)

A tool which performs a backup of a given directory to a data storage device in the cloud
The tool will be executed on linux-lab.cs.stevens.edu.

## Usage

Make sure you have the following environment variables set:

    export EC2_BACKUP_FLAGS_SSH="-i <YOUR PRIVATE KEY FILE PATH>"
    export EC2_BACKUP_FLAGS_AWS="--security-groups <SECURITY GROUP NAME> --key-name <KEY PAIR NAME>"

Set the variable `EC2_BACKUP_VERBOSE` to produce verbose output(optional):


    export EC2_BACKUP_VERBOSE="true"

---

We implemented it by **bash** as bash is good at automating command line tasks. The program has 3 main parts: instance creation, volume creation/attaching and back-up functions.

The problems that we ran into:

1. At first we can not make it to write a workable backing-up function, after some study we found that we need to specify the output of the dd command to a file on the mounted filesystem.
2. After the creation of an instance, we can not manage to log in to the server via `ssh`. After debugging we found that this is because we need leave some time for the instance to get up and running, so we wrote some logics to wait for the instance status to be changed to `running` before the program perform any further operations.
