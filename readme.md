# Kubernetes and Docker on Mac and Windows

## Quick jump
- [Mac / Hyperkit](#mac--hyperkit)
- [Windows / Hyper-V](#windows--hyper-v)

## Supported scenarios
- Multi-node (or single-node) Kubernetes on CentOS/Ubuntu in Hyper-V/Hyperkit
- Docker on Desktop without Docker for Desktop

## Advantages
- TODO
- minimalistic
- simplicity

## Limitations
- TODO
- no cifs events/osx share; hyperkit time sync;

## Changelog
- Current state: pre-release; do not use yet;

# Mac / Hyperkit
```bash

# tested on Hyperkit 0.20190802 on macOS 10.14.5 w/ APFS, guest images Centos 1907 and Ubuntu 18.04
# note: `sudo` is necessary for access to macOS Hypervisor and vmnet frameworks, and /etc/hosts config

# download the script
cd workdir
curl https://raw.githubusercontent.com/youurayy/hyperctl/master/hyperctl.sh -O
chmod +x hyperctl.sh

# display short synopsis for the available commands
./hyperctl.sh
'
  Usage: ./hyperctl.sh command+

  Commands:

     install - install basic homebrew packages
      config - show script config vars
       print - print contents of relevant config files
         net - create or reset the vmnet config
        dhcp - append to the dhcp registry
       hosts - append node names to etc/hosts
       image - download the VM image
      master - create and launch master node
       nodeN - create and launch worker node (node1, node2, ...)
        info - display info about nodes
        init - initialize k8s and setup host kubectl
      reboot - soft-reboot the nodes
    shutdown - soft-shutdown the nodes
        stop - stop the VMs
       start - start the VMs
        kill - force-stop the VMs
      delete - delete the VM files
         iso - write cloud config data into a local yaml
    timesync - setup sleepwatcher time sync
      docker - setup local docker with the master node
       share - setup local fs sharing with docker on master
'

# performs `brew install hyperkit qemu kubernetes-cli kubernetes-helm`.
# (qemu is necessary for `qemu-img`)
# you may perform these manually / selectively instead.
./hyperctl.sh install

# display configured variables (edit the script to change them)
# note: to quickly change distro, do `echo bionic >> .distro`
./hyperctl.sh config
'
    CONFIG: centos
    DISTRO: centos
   WORKDIR: ./tmp
 GUESTUSER: user
   SSHPATH: /Users/user/.ssh/id_rsa.pub
  IMAGEURL: https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud-1907.raw.tar.gz
  DISKFILE: CentOS-7-x86_64-GenericCloud-1907.raw
      CIDR: 10.10.0.0/24
      CPUS: 4
       RAM: 4GB
       HDD: 40G
       CNI: flannel
    CNINET: 10.244.0.0/16
   CNIYAML: https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
 DOCKERCLI: https://download.docker.com/mac/static/stable/x86_64/docker-19.03.1.tgz
'

# print external configs that this script can change
./hyperctl.sh print

# cleans or creates /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist
# and sets the CIDR configured in the script.
# if other apps already use the vmnet framework, then you don't want to change it, in
# which case don't run this command, but instead set the CIDR inside this script
# to the value from the vmnet.plist (as shown by the 'print' command).
./hyperctl.sh net

# appends IPs and MACs from the NODES config to the /var/db/dhcpd_leases.
# this is necessary to have predictable IPs.
# (MACs are generated from UUIDs by the vmnet framework.)
./hyperctl.sh dhcp

# appends IP/hostname pairs from the NODES config to the /etc/hosts.
# (the same hosts entries will also be installed into every node)
./hyperctl.sh hosts

# download, prepare and cache the VM image templates
./hyperctl.sh image

# create/launch the nodes
./hyperctl.sh master
./hyperctl.sh node1
./hyperctl.sh nodeN...
# ---- or -----
./hyperctl.sh master node1 node2 nodeN...

# ssh to the nodes if necessary (e.g. for manual k8s init)
# by default, your `.ssh/id_rsa.pub` key was copied into the VMs' ~/.ssh/authorized_keys
# uses your host username (which is the default), e.g.:
ssh master
ssh node1
ssh node2
...

# performs automated k8s init (will wait for VMs to finish init first)
./hyperctl.sh init

# after init, you can do e.g.:
hyperctl get pods --all-namespaces
'
NAMESPACE     NAME                             READY   STATUS    RESTARTS   AGE
kube-system   coredns-5c98db65d4-b92p9         1/1     Running   1          5m31s
kube-system   coredns-5c98db65d4-dvxvr         1/1     Running   1          5m31s
kube-system   etcd-master                      1/1     Running   1          4m36s
kube-system   kube-apiserver-master            1/1     Running   1          4m47s
kube-system   kube-controller-manager-master   1/1     Running   1          4m46s
kube-system   kube-flannel-ds-amd64-6kj9p      1/1     Running   1          5m32s
kube-system   kube-flannel-ds-amd64-r87qw      1/1     Running   1          5m7s
kube-system   kube-flannel-ds-amd64-wdmxs      1/1     Running   1          4m43s
kube-system   kube-proxy-2p2db                 1/1     Running   1          5m32s
kube-system   kube-proxy-fg8k2                 1/1     Running   1          5m7s
kube-system   kube-proxy-rtjqv                 1/1     Running   1          4m43s
kube-system   kube-scheduler-master            1/1     Running   1          4m38s
'

# reboot the nodes
./hyperctl.sh reboot

# show info about existing VMs (size, run state)
./hyperctl.sh info
'
NAME    PID    %CPU  %MEM  RSS   STARTED  TIME     DISK  SPARSE  STATUS
master  36399  0.4   2.1   341M  3:51AM   0:26.30  40G   3.1G    RUNNING
node1   36418  0.3   2.1   341M  3:51AM   0:25.59  40G   3.1G    RUNNING
node2   37799  0.4   2.0   333M  3:56AM   0:16.78  40G   3.1G    RUNNING
'

# shutdown all nodes thru ssh
./hyperctl.sh shutdown

# start all nodes
./hyperctl.sh start

# stop all nodes
./hyperctl.sh stop

# force-stop all nodes
./hyperctl.sh kill

# delete all nodes' data (will not delete image templates)
./hyperctl.sh delete

# kill only a particular node
sudo kill -TERM 36418

# delete only a particular node
rm -rf ./tmp/node1/

# remove everything
sudo killall -9 hyperkit
rm -rf ./tmp

# exports the cloud-init yaml into ./$distro.yaml for review
./hyperctl.sh iso

# installs and configures sleepwatcher to call this script to update the
# VMs clocks after your Mac wakes up from sleep
./hyperctl.sh timesync

# installs local docker cli (docker.exe) and helps you configure it to connect
# to the docker running on the master node
./hyperctl.sh docker

# walks you through a file sharing setup between local machine and the master node,
# so that you can work with docker volumes.
# this is semi-interactive so that your password is never stored anywhere insecurely.
# this also means that you have to repeat this if you restart the master node.
# alternatively, you can add the mount into master's fstab with a password= option.
# note: the SMB file sharing does not support filesystem inotify events.
./hyperctl.sh share

```

# Windows / Hyper-V
```powershell

# tested with PowerShell 5.1 on Windows 10 Pro 1903, guest images Centos 1907 and Ubuntu 18.04
# note: admin access is necessary for access to Windows Hyper-V framework and etc/hosts config

# open PowerShell (Admin) prompt
cd $HOME\your-workdir

# download the script
curl https://raw.githubusercontent.com/youurayy/hyperctl/master/hyperctl.ps1 -outfile hyperctl.ps1
# enable script run permission
set-executionpolicy remotesigned

# display short synopsis for the available commands
.\hyperctl.ps1
'
  Usage: .\hyperctl.ps1 command+

  Commands:

     install - install basic chocolatey packages
      config - show script config vars
       print - print etc/hosts, network interfaces and mac addresses
         net - install private or public host network
       hosts - append private network node names to etc/hosts
       image - download the VM image
      master - create and launch master node
       nodeN - create and launch worker node (node1, node2, ...)
        info - display info about nodes
        init - initialize k8s and setup host kubectl
      reboot - soft-reboot the nodes
    shutdown - soft-shutdown the nodes
        save - snapshot the VMs
     restore - restore VMs from latest snapshots
        stop - stop the VMs
       start - start the VMs
      delete - stop VMs and delete the VM files
      delnet - delete the network
         iso - write cloud config data into a local yaml
      docker - setup local docker with the master node
       share - setup local fs sharing with docker on master
        helm - setup helm cli
'

# performs `choco install 7zip.commandline qemu-img kubernetes-cli kubernetes-helm`.
# you may instead perform these manually / selectively instead.
# note: 7zip is needed to extract .xz archives
# note: qemu-img is needed convert images to vhdx
.\hyperctl.ps1 install

# display configured variables (edit the script to change them)
# note: to quickly change distro, do e.g. `echo centos >> .distro`
.\hyperctl.ps1 config
'
    config: bionic
    distro: ubuntu
   workdir: .\tmp
 guestuser: user
   sshpath: C:\Users\user\.ssh\id_rsa.pub
  imageurl: https://cloud-images.ubuntu.com/releases/server/18.04/release/ubuntu-18.04-server-cloudimg-amd64.img
  vhdxtmpl: .\tmp\ubuntu-18.04-server-cloudimg-amd64.vhdx
      cidr: 10.10.0.0/24
    switch: switch
   nettype: private
    natnet: natnet
      cpus: 4
       ram: 4GB
       hdd: 40GB
       cni: flannel
    cninet: 10.244.0.0/16
   cniyaml: https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
 dockercli: https://github.com/StefanScherer/docker-cli-builder/releases/download/19.03.1/docker.exe
'

# print relevant configuration - etc/hosts, mac addresses, network interfaces
.\hyperctl.ps1 print

# create a private network for the VMs, as set by the `cidr` variable
.\hyperctl.ps1 net

# appends IP/hostname pairs to the /etc/hosts.
# (the same hosts entries will also be installed into every node)
.\hyperctl.ps1 hosts

# download, prepare and cache the VM image templates
.\hyperctl.ps1 image

# create/launch the nodes
.\hyperctl.ps1 master
.\hyperctl.ps1 node1
.\hyperctl.ps1 nodeN...
# ---- or -----
.\hyperctl.ps1 master node1 node2 nodeN...

# ssh to the nodes if necessary (e.g. for manual k8s init)
# by default, your `.ssh/id_rsa.pub` key was copied into the VMs' ~/.ssh/authorized_keys
# uses your host username (which is the default), e.g.:
ssh master
ssh node1
ssh node2
...

# perform automated k8s init (will wait for VMs to finish init first)
# (this will checkpoint the nodes just before `kubeadm init`)
.\hyperctl.ps1 init

# after init, you can do e.g.:
hyperctl get pods --all-namespaces
'
NAMESPACE     NAME                             READY   STATUS    RESTARTS   AGE
kube-system   coredns-5c98db65d4-b92p9         1/1     Running   1          5m31s
kube-system   coredns-5c98db65d4-dvxvr         1/1     Running   1          5m31s
kube-system   etcd-master                      1/1     Running   1          4m36s
kube-system   kube-apiserver-master            1/1     Running   1          4m47s
kube-system   kube-controller-manager-master   1/1     Running   1          4m46s
kube-system   kube-flannel-ds-amd64-6kj9p      1/1     Running   1          5m32s
kube-system   kube-flannel-ds-amd64-r87qw      1/1     Running   1          5m7s
kube-system   kube-flannel-ds-amd64-wdmxs      1/1     Running   1          4m43s
kube-system   kube-proxy-2p2db                 1/1     Running   1          5m32s
kube-system   kube-proxy-fg8k2                 1/1     Running   1          5m7s
kube-system   kube-proxy-rtjqv                 1/1     Running   1          4m43s
kube-system   kube-scheduler-master            1/1     Running   1          4m38s
'

# reboot the nodes
.\hyperctl.ps1 reboot

# show info about existing VMs (size, run state)
.\hyperctl.ps1 info
'
Name   State   CPUUsage(%) MemoryAssigned(M) Uptime           Status             Version
----   -----   ----------- ----------------- ------           ------             -------
master Running 3           5908              00:02:25.5770000 Operating normally 9.0
node1  Running 8           4096              00:02:22.7680000 Operating normally 9.0
node2  Running 2           4096              00:02:20.1000000 Operating normally 9.0
'

# checkpoint the VMs
.\hyperctl.ps1 save

# restore the VMs from the lastest snapshot
.\hyperctl.ps1 restore

# shutdown all nodes thru ssh
.\hyperctl.ps1 shutdown

# start all nodes
.\hyperctl.ps1 start

# stop all nodes thru hyper-v
.\hyperctl.ps1 stop

# delete all nodes' data (will not delete image templates)
.\hyperctl.ps1 delete

# delete the network
.\hyperctl.ps1 delnet

# installs local docker cli (docker.exe) and helps you configure it to connect
# to the docker running on the master node
.\hyperctl.ps1 docker

# walks you through a file sharing setup between local machine and the master node,
# so that you can work with docker volumes.
# this is semi-interactive so that your password is never stored anywhere insecurely.
# this also means that you have to repeat this if you restart the master node.
# alternatively, you can add the mount into master's fstab with a password= option.
.\hyperctl.ps1 share

# NOTE if Hyper-V stops working after a Windows update, do:
# Windows Security -> App & Browser control -> Exploit protection settings -> Program settings ->
# C:\WINDOWS\System32\vmcompute.exe -> Edit-> Code flow guard (CFG) ->
# uncheck Override system settings -> # net stop vmcompute -> net start vmcompute

```

#### License: https://www.apache.org/licenses/LICENSE-2.0
