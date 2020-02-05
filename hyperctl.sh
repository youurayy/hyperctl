#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# For usage overview, read the readme.md at https://github.com/youurayy/hyperctl

# ---------------------------SETTINGS------------------------------------

VERSION="v1.0.1"
WORKDIR="./tmp"
GUESTUSER=$USER
SSHPATH="$HOME/.ssh/id_rsa.pub"
if ! [ -a $SSHPATH ]; then
  echo -e "\\n please configure $sshpath or place a pubkey at $sshpath \\n"
  exit
fi
SSHPUB=$(cat $SSHPATH)

CONFIG=$(cat .distro 2> /dev/null)
CONFIG=${CONFIG:-"centos"}

case $CONFIG in
  bionic)
    DISTRO="ubuntu"
    IMGVERS="18.04"
    IMAGE="ubuntu-$IMGVERS-server-cloudimg-amd64"
    IMAGEURL="https://cloud-images.ubuntu.com/releases/server/$IMGVERS/release"
    SHA256FILE="SHA256SUMS"
    KERNURL="https://cloud-images.ubuntu.com/releases/server/$IMGVERS/release/unpacked"
    KERNEL="$IMAGE-vmlinuz-generic"
    INITRD="$IMAGE-initrd-generic"
    IMGTYPE="vmdk"
    ARCHIVE=
  ;;
  disco)
    DISTRO="ubuntu"
    IMGVERS="19.04"
    IMAGE="ubuntu-$IMGVERS-server-cloudimg-amd64"
    IMAGEURL="https://cloud-images.ubuntu.com/releases/server/$IMGVERS/release"
    SHA256FILE="SHA256SUMS"
    KERNURL="https://cloud-images.ubuntu.com/releases/server/$IMGVERS/release/unpacked"
    KERNEL="$IMAGE-vmlinuz-generic"
    INITRD="$IMAGE-initrd-generic"
    IMGTYPE="vmdk"
    ARCHIVE=""
  ;;
  centos)
    DISTRO="centos"
    IMGVERS="1907"
    IMAGE="CentOS-7-x86_64-GenericCloud-$IMGVERS"
    IMAGEURL="https://cloud.centos.org/centos/7/images"
    SHA256FILE="sha256sum.txt"
    KERNURL="https://github.com/youurayy/hyperctl/releases/download/centos-kernel/"
    KERNEL="vmlinuz-3.10.0-957.27.2.el7.x86_64"
    INITRD="initramfs-3.10.0-957.27.2.el7.x86_64.img"
    IMGTYPE="raw"
    ARCHIVE=".tar.gz"
  ;;
esac

CIDR="10.10.0"
CMDLINE="earlyprintk=serial console=ttyS0 root=/dev/sda1" # root=LABEL=cloudimg-rootfs
ISO="cloud-init.iso"

CPUS=4
RAM=4GB
HDD=40G

FORMAT="raw"
FILEPREFIX=""
DISKOPTS=""

# FORMAT="qcow2"
# FILEPREFIX="file://"
# DISKOPTS=",format=qcow"

DISKDEV="ahci-hd"
# DISKDEV="virtio-blk"

# user for debug/tty:
# BACKGROUND=
# use for prod/ssh:
BACKGROUND='> output.log 2>&1 &'

NODES=(
  "master 24AF0C19-3B96-487C-92F7-584C9932DD96 $CIDR.10 32:a2:b4:36:57:16"
  "node1  B0F97DC5-5E9F-40FC-B829-A1EF974F5640 $CIDR.11 46:5:bd:af:97:f"
  "node2  0BD5B90C-E00C-4E1B-B3CF-117D6FF3C09F $CIDR.12 c6:b7:b1:30:6:fd"
  "node3  7B822993-5E08-41D4-9FB6-8F9FD31C9AD8 $CIDR.13 86:eb:d9:e1:f2:ce"
  "node4  384C454E-B22B-4945-A33F-2E3E2E9F74B4 $CIDR.14 ae:33:94:63:3a:8f"
  "node5  BEC17A85-E2B4-480F-B86C-808412E21823 $CIDR.15 f2:66:d8:80:e5:bd"
  "node6  F6C972A8-0B73-4C72-9F7C-202AAC773DD8 $CIDR.16 92:50:d8:18:86:d5"
  "node7  F05E1728-7403-46CF-B88E-B243D754B800 $CIDR.17 86:d6:cf:41:e0:3e"
  "node8  38659F47-3A64-49E3-AE6E-B41F6A42E1D1 $CIDR.18 ca:c5:12:22:d:ce"
  "node9  20DD5167-9FBE-439E-9849-E324E984FB96 $CIDR.19 f6:d4:b9:fd:20:c"
)

KUBEPACKAGES_latest="\
  - docker-ce
  - docker-ce-cli
  - containerd.io
  - kubelet
  - kubeadm
  - kubectl
"

KUBEPACKAGES_mid_2019="\
  - [ docker-ce, 19.03.1 ]
  - [ docker-ce-cli, 19.03.1 ]
  - [ containerd.io, 1.2.6 ]
  - [ kubelet, 1.15.3 ]
  - [ kubeadm, 1.15.3 ]
  - [ kubectl, 1.15.3 ]
"

KUBEPACKAGES=$KUBEPACKAGES_mid_2019

CNI="flannel"

case $CNI in
  flannel)
    CNIYAML="https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
    CNINET="10.244.0.0/16"
  ;;
  weave)
    CNIYAML='https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d "\n")'
    CNINET="10.32.0.0/12"
  ;;
  calico)
    CNIYAML="https://docs.projectcalico.org/v3.7/manifests/calico.yaml"
    CNINET="192.168.0.0/16"
  ;;
esac

SSHOPTS="-o ConnectTimeout=5 -o LogLevel=ERROR -o StrictHostKeyChecking=false -o UserKnownHostsFile=/dev/null"

DOCKERCLI="https://download.docker.com/mac/static/stable/x86_64/docker-19.03.1.tgz"

HELMURL="https://get.helm.sh/helm-v3.0.3-darwin-amd64.tar.gz"

# -------------------------CLOUD INIT-----------------------------------

cloud-init() {
USERDATA_shared="\
#cloud-config

mounts:
  - [ swap ]

groups:
  - docker

users:
  - name: $GUESTUSER
    ssh_authorized_keys:
      - '$SSHPUB'
    sudo: [ 'ALL=(ALL) NOPASSWD:ALL' ]
    groups: [ sudo, docker ]
    shell: /bin/bash
    # lock_passwd: false # passwd won't work without this
    # passwd: '\$6\$rounds=4096\$byY3nxArmvpvOrpV\$2M4C8fh3ZXx10v91yzipFRng1EFXTRNDE3q9PvxiPc3kC7N/NHG8HiwAvhd7QjMgZAXOsuBD5nOs0AJkByYmf/' # 'test'

write_files:
  # resolv.conf hard-set is a workaround for intial setup
  - path: /tmp/append-etc-hosts
    content: |
      $(etc-hosts '      ')
  - path: /etc/resolv.conf
    content: |
      nameserver 8.8.4.4
      nameserver 8.8.8.8
  - path: /etc/systemd/resolved.conf
    content: |
      [Resolve]
      DNS=8.8.4.4
      FallbackDNS=8.8.8.8
  - path: /etc/modules-load.d/k8s.conf
    content: |
      br_netfilter
  - path: /etc/sysctl.d/k8s.conf
    content: |
      net.bridge.bridge-nf-call-ip6tables = 1
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-arptables = 1
      net.ipv4.ip_forward = 1
  - path: /etc/docker/daemon.json
    content: |
      {
        \"exec-opts\": [\"native.cgroupdriver=systemd\"],
        \"log-driver\": \"json-file\",
        \"log-opts\": {
          \"max-size\": \"100m\"
        },
        \"storage-driver\": \"overlay2\",
        \"storage-opts\": [
          \"overlay2.override_kernel_check=true\"
        ]
      }"

USERDATA_centos="\
$USERDATA_shared
  # https://github.com/kubernetes/kubernetes/issues/56850
  - path: /usr/lib/systemd/system/kubelet.service.d/12-after-docker.conf
    content: |
      [Unit]
      After=docker.service

yum_repos:
  docker-ce-stable:
    name: Docker CE Stable - \$basearch
    baseurl: https://download.docker.com/linux/centos/7/\$basearch/stable
    enabled: 1
    gpgcheck: 1
    gpgkey: https://download.docker.com/linux/centos/gpg
    priority: 1
  kubernetes:
    name: Kubernetes
    baseurl: https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
    enabled: 1
    gpgcheck: 1
    repo_gpgcheck: 1
    gpgkey: https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
    priority: 1

package_upgrade: true

packages:
  - yum-utils
  - cifs-utils
  - device-mapper-persistent-data
  - lvm2
$KUBEPACKAGES

runcmd:
  - echo 'sudo tail -f /var/log/messages' > /home/$GUESTUSER/log
  - cat /tmp/append-etc-hosts >> /etc/hosts
  - setenforce 0
  - sed -i 's/^SELINUX=enforcing\$/SELINUX=permissive/' /etc/selinux/config
  - mkdir -p /etc/systemd/system/docker.service.d
  - systemctl disable firewalld
  - systemctl daemon-reload
  - systemctl enable docker
  - systemctl enable kubelet
  # https://github.com/kubernetes/kubeadm/issues/954
  - echo 'exclude=kube*' >> /etc/yum.repos.d/kubernetes.repo
  # https://github.com/kubernetes/kubernetes/issues/76531
  - curl -L 'https://github.com/youurayy/runc/releases/download/v1.0.0-rc8-slice-fix-2/runc-centos.tgz' | tar --backup=numbered -xzf - -C \$(dirname \$(which runc))
  - systemctl start docker
  - touch /home/$GUESTUSER/.init-completed"

USERDATA_ubuntu="\
$USERDATA_shared
  # https://github.com/kubernetes/kubernetes/issues/56850
  - path: /etc/systemd/system/kubelet.service.d/12-after-docker.conf
    content: |
      [Unit]
      After=docker.service
  - path: /etc/apt/preferences.d/docker-pin
    content: |
      Package: *
      Pin: origin download.docker.com
      Pin-Priority: 600
  - path: /etc/systemd/network/99-default.link
    content: |
      [Match]
      Path=/devices/virtual/net/*
      [Link]
      NamePolicy=kernel database onboard slot path
      MACAddressPolicy=none

apt:
  sources:
    kubernetes:
      source: 'deb http://apt.kubernetes.io/ kubernetes-xenial main'
      keyserver: 'hkp://keyserver.ubuntu.com:80'
      keyid: BA07F4FB
    docker:
      arches: amd64
      source: 'deb https://download.docker.com/linux/ubuntu bionic stable'
      keyserver: 'hkp://keyserver.ubuntu.com:80'
      keyid: 0EBFCD88

package_upgrade: true

packages:
  - cifs-utils
  - chrony
$KUBEPACKAGES

runcmd:
  - echo 'sudo tail -f /var/log/syslog' > /home/$GUESTUSER/log
  - systemctl mask --now systemd-timesyncd
  - systemctl enable --now chrony
  - systemctl stop kubelet
  - cat /tmp/append-etc-hosts >> /etc/hosts
  - chmod o+r /lib/systemd/system/kubelet.service
  - chmod o+r /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
  # https://github.com/kubernetes/kubeadm/issues/954
  - apt-mark hold kubeadm kubelet
  # https://github.com/kubernetes/kubernetes/issues/76531
  - curl -L 'https://github.com/youurayy/runc/releases/download/v1.0.0-rc8-slice-fix-2/runc-ubuntu.tbz' | tar --backup=numbered -xjf - -C \$(dirname \$(which runc))
  - touch /home/$GUESTUSER/.init-completed"
}

# ----------------------------------------------------------------------

set -e

BASEDIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)

hyperctl="kubectl --kubeconfig $HOME/.kube/config.hyperctl"

DHCPD_LEASES='/var/db/dhcpd_leases'
VMMET_PLIST='/Library/Preferences/SystemConfiguration/com.apple.vmnet.plist'

go-to-scriptdir() {
  cd $BASEDIR
}

get_host() {
  echo ${NODES[$1]} | awk '{ print $1 }'
}

get_uuid() {
  echo ${NODES[$1]} | awk '{ print $2 }'
}

get_ip() {
  echo ${NODES[$1]} | awk '{ print $3 }'
}

get_mac() {
  echo ${NODES[$1]} | awk '{ print $4 }'
}

dhcpd-leases() {
cat << EOF | sudo tee -a $DHCPD_LEASES
$(for i in `seq 0 1 9`; do echo "{
        name=$(get_host $i)
        ip_address=$(get_ip $i)
        hw_address=1,$(get_mac $i)
        identifier=1,$(get_mac $i)
}"; done)
EOF
}

etc-hosts() {
cat << EOF
#
$1#
$(for i in `seq 0 1 9`; do echo -e "$1$(get_ip $i) $(get_host $i)"; done)
$1#
$1#
EOF
}

download-image() {
  go-to-scriptdir
  mkdir -p $WORKDIR && cd $WORKDIR

  if ! [ -a $IMAGE.$IMGTYPE ]; then
    curl $IMAGEURL/$IMAGE.$IMGTYPE$ARCHIVE -O
    shasum -a 256 -c <(curl -s $IMAGEURL/$SHA256FILE | grep "$IMAGE.$IMGTYPE$ARCHIVE")

    if [ "$ARCHIVE" = ".tar.gz" ]; then
      tar xzf $IMAGE.$IMGTYPE$ARCHIVE
    fi

    if [ -n "$KERNURL" ]; then
      curl -L $KERNURL/$KERNEL -O
      curl -L $KERNURL/$INITRD -O
      shasum -a 256 -c <(curl -s -L $KERNURL/$SHA256FILE | grep "$KERNEL")
      shasum -a 256 -c <(curl -s -L $KERNURL/$SHA256FILE | grep "$INITRD")
    fi
  fi
}

is-machine-running() {
  ps -p $(cat $1/machine.pid 2> /dev/null) > /dev/null 2>&1
}

start-machine() {
  sudo ./cmdline

  if [ -z "$BACKGROUND" ]; then
    rm -f machine.pid
  else
    echo "started PID $(cat machine.pid)"
  fi
}

write-user-data() {
  cloud-init
  varname=USERDATA_$DISTRO

cat << EOF > $1
${!varname}
EOF
}

create-machine() {

  if [ -z $UUID ] || [ -z $NAME ] || [ -z $CPUS ] || [ -z $RAM ] || [ -z $DISK ]; then
    echo "create-machine: invalid params"
    return
  fi

  echo "starting machine $NAME"

  go-to-scriptdir
  mkdir -p $WORKDIR/$NAME && cd $WORKDIR/$NAME

  if is-machine-running ../$NAME; then
    echo "machine is already running!"
    return
  fi

  mkdir -p cidata

cat << EOF > cidata/meta-data
instance-id: id-$NAME
local-hostname: $NAME
EOF

  write-user-data "cidata/user-data"

  rm -f $ISO
  hdiutil makehybrid -iso -joliet -o $ISO cidata

  DISKFILE="$IMAGE.$FORMAT"

  if ! [ -a $DISKFILE ]; then
    echo Creating $(pwd)/$DISKFILE

    if [ $FORMAT != $IMGTYPE ]; then
      qemu-img convert -O $FORMAT ../$IMAGE.$IMGTYPE $DISKFILE
    else
      cp ../$IMAGE.$IMGTYPE $DISKFILE
    fi

    qemu-img resize -f $FORMAT $DISKFILE $DISK
  fi

cat << EOF > cmdline
exec hyperkit -A \
  -H \
  -U $UUID \
  -m $RAM \
  -c $CPUS \
  -s 0:0,hostbridge \
  -s 2:0,virtio-net \
  -s 31,lpc \
  -l com1,stdio \
  -s 1:0,$DISKDEV,$FILEPREFIX$(pwd)/$DISKFILE$DISKOPTS \
  -s 5,ahci-cd,$(pwd)/$ISO \
  -f "kexec,../$KERNEL,../$INITRD,$CMDLINE" $BACKGROUND
echo \$! > machine.pid
EOF

  chmod +x cmdline
  cat cmdline

  start-machine
}

create-vmnet() {
cat << EOF | sudo tee $VMMET_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Shared_Net_Address</key>
  <string>$CIDR.1</string>
  <key>Shared_Net_Mask</key>
  <string>255.255.255.0</string>
</dict>
</plist>
EOF
}

proc-list() {
  echo $1
  ps auxw | grep hyperkit
}

node-info() {
  if is-machine-running $1; then
    etc=$(ps uxw -p $(cat $1/machine.pid 2> /dev/null) 2> /dev/null | tail -n 1 | awk '{ printf("%s\t%s\t%s\t%s\t%s\t%s", $2, $3, $4, int($6/1024)"M", $9, $10); }')
  else
    etc='-\t-\t-\t-\t-\t-'
  fi
  name=$(basename $1)
  disk=$(ls -lh $1/*.$FORMAT | awk '{print $5}')
  sparse=$(du -h $1/*.$FORMAT | awk '{print $1}')
  status=$(if is-machine-running $1; then echo "RUNNING"; else echo "NOT RUNNING"; fi)
  echo -e "$name\\t$etc\\t$disk\\t$sparse\\t$status"
}

get-all-nodes() {
  find $WORKDIR/* -maxdepth 0 -type d |
    while read node; do echo -n " "`basename $node`; done
}

get-worker-nodes() {
  find $WORKDIR/* -maxdepth 0 -type d -not -name master |
    while read node; do echo -n " "`basename $node`; done
}

exec-on-all-nodes() {
  go-to-scriptdir
  allnodes=( $(get-all-nodes) )
  for node in ${allnodes[@]}; do
    echo ---------------------$node
    ssh $SSHOPTS $GUESTUSER@$node $1
  done
}

wait-for-node-init() {
  node=$1
  while ! ssh $SSHOPTS $GUESTUSER@$node 'ls ~/.init-completed > /dev/null 2>&1'; do
    echo "waiting for $node to init..."
    sleep 5
  done
}

kill_all_vms() {
  go-to-scriptdir
  sudo find $WORKDIR -name machine.pid -exec sh -c 'kill -9 $(cat $1)' sh {} ';'
}

print-local-repo-tips() {
cat << EOF
# you can now publish your apps, e.g.:

TAG=master:30699/yourapp:$(git log --pretty=format:'%h' -n 1)
docker build ../yourapp/image/ --tag $TAG
docker push $TAG
hyperhelm install yourapp ../yourapp/chart/ --set image=$TAG
EOF
}

help() {
cat << EOF
  Practice real Kubernetes configurations on a local multi-node cluster.
  Inspect and optionally customize this script before use.

  Usage: ./hyperctl.sh command+

  Commands:

     (pre-requisites are marked with ->)

  -> install - install basic homebrew packages
      config - show script config vars
       print - print contents of relevant config files
  ->     net - create or update the vmnet config
  ->    dhcp - append to the dhcp registry
       reset - reset the vmnet and dhpc configs
  ->   hosts - append node names to etc/hosts
  ->   image - download the VM image
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
       helm2 - setup helm 2 with tiller in k8s
       helm3 - setup helm 3
        repo - install local docker repo in k8s

  For more info, see: https://github.com/youurayy/hyperctl
EOF
}

echo

if [ $# -eq 0 ]; then help; fi

for arg in "$@"; do
  case $arg in
    install)
      if ! which hyperkit > /dev/null; then
        brew install hyperkit
      fi
      if ! which qemu-img > /dev/null; then
        brew install qemu
      fi
      if ! which kubectl > /dev/null; then
        brew install kubernetes-cli
      fi
    ;;
    config)
      echo "   VERSION: $VERSION"
      echo "    CONFIG: $CONFIG"
      echo "    DISTRO: $DISTRO"
      echo "   WORKDIR: $WORKDIR"
      echo " GUESTUSER: $GUESTUSER"
      echo "   SSHPATH: $SSHPATH"
      echo "  IMAGEURL: $IMAGEURL/$IMAGE.$IMGTYPE$ARCHIVE"
      echo "  DISKFILE: $IMAGE.$FORMAT"
      echo "      CIDR: $CIDR.0/24"
      echo "      CPUS: $CPUS"
      echo "       RAM: $RAM"
      echo "       HDD: $HDD"
      echo "       CNI: $CNI"
      echo "    CNINET: $CNINET"
      echo "   CNIYAML: $CNIYAML"
      echo " DOCKERCLI: $DOCKERCLI"
    ;;
    print)
      sudo echo

      echo "***** com.apple.vmnet.plist *****"
      sudo cat $VMMET_PLIST || true

      echo "***** $DHCPD_LEASES *****"
      cat $DHCPD_LEASES || true

      echo "***** /etc/hosts *****"
      cat /etc/hosts
    ;;
    net)
      create-vmnet
    ;;
    dhcp)
      dhcpd-leases
    ;;
    reset)
      sudo rm -f \
        $VMMET_PLIST \
        $DHCPD_LEASES
      echo -e "deleted\n  $VMMET_PLIST\nand\n  $DHCPD_LEASES\n\n" \
        "-> you sould reboot now, then use ./hyperkit.sh net dhcp"
    ;;
    hosts)
      echo "$(etc-hosts)" | sudo tee -a /etc/hosts
    ;;
    image)
      download-image
    ;;
    master)
      UUID=$(get_uuid 0) NAME=master CPUS=$CPUS RAM=$RAM DISK=$HDD create-machine
    ;;
    node*)
      num=$(echo $arg | sed -E 's:node(.+):\1:')
      UUID=$(get_uuid $num) NAME=$arg CPUS=$CPUS RAM=$RAM DISK=$HDD create-machine
    ;;
    info)
      go-to-scriptdir
      { echo -e 'NAME\tPID\t%CPU\t%MEM\tRSS\tSTARTED\tTIME\tDISK\tSPARSE\tSTATUS' &
      find $WORKDIR/* -maxdepth 0 -type d | while read node; do node-info "$node"; done } | column -ts $'\t'
    ;;
    init)
      go-to-scriptdir
      allnodes=( $(get-all-nodes) )
      workernodes=( $(get-worker-nodes) )

      for node in ${allnodes[@]}; do
        wait-for-node-init $node
      done

      echo "all nodes are pre-initialized, going to init k8s..."

      init="sudo kubeadm init --pod-network-cidr=$CNINET &&
        mkdir -p \$HOME/.kube &&
        sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config &&
        sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config &&
        kubectl apply -f \$(eval echo $CNIYAML)"

      echo "executing on master: $init"

      if ! ssh $SSHOPTS $GUESTUSER@master $init; then
        echo "master init has failed, aborting"
        exit 1
      fi

      if [ "${#workernodes[@]}" -eq 0 ]; then
        echo
        echo "no worker nodes, removing NoSchedule taint from master..."
        ssh $SSHOPTS $GUESTUSER@master 'kubectl taint nodes master node-role.kubernetes.io/master:NoSchedule-'
        echo
      else
        joincmd=$(ssh $SSHOPTS $GUESTUSER@master 'sudo kubeadm token create --print-join-command')
        for node in ${workernodes[@]}; do
          echo "executing on $node: $joincmd"
          ssh $SSHOPTS $GUESTUSER@$node "sudo $joincmd < /dev/null"
        done
      fi

      mkdir -p ~/.kube
      scp $SSHOPTS $GUESTUSER@master:.kube/config ~/.kube/config.hyperctl

      cachedir="$HOME/.kube/cache/discovery/$CIDR.10_6443/"
      if [ -a $cachedir ]; then
        echo
        echo "deleting previous $cachedir"
        echo
        rm -rf $cachedir
      fi

      echo
      $hyperctl get pods --all-namespaces
      $hyperctl get nodes
      echo
      echo "to setup bash alias, exec:"
      echo
      echo "echo \"alias hyperctl='$hyperctl'\" >> ~/.profile"
      echo "source ~/.profile"
    ;;
    reboot)
      exec-on-all-nodes "sudo reboot"
    ;;
    shutdown)
      exec-on-all-nodes "sudo shutdown -h now"
    ;;
    stop)
      go-to-scriptdir
      sudo find $WORKDIR -name machine.pid -exec sh -c 'kill -TERM $(cat $1)' sh {} ';'
    ;;
    start)
      allnodes=( $(get-all-nodes) )
      for node in ${allnodes[@]}; do
        echo "starting $node..."
        go-to-scriptdir
        cd $WORKDIR/$node
        start-machine
      done
    ;;
    kill)
      kill_all_vms
    ;;
    delete)
      kill_all_vms
      go-to-scriptdir
      find $WORKDIR/* -maxdepth 0 -type d -exec rm -rf {} ';'
    ;;
    timesync)
      brew install sleepwatcher
      brew services start sleepwatcher
      echo "$BASEDIR/hyperctl.sh hwclock" >> ~/.wakeup
      chmod +x ~/.wakeup
      echo "time sync added to ~/.wakeup"
      echo
      cat ~/.wakeup
    ;;
    hwclock)
      exec-on-all-nodes "date ; sudo hwclock -s; date"
    ;;
    time)
      echo "local: $(date)"
      exec-on-all-nodes "date ; sudo chronyc makestep ; date"
    ;;
    track)
      exec-on-all-nodes "date ; sudo chronyc tracking"
    ;;
    docker)
      if ! which docker > /dev/null; then
        echo "installing docker cli..."
        curl -L $DOCKERCLI | tar zxvf - --strip 1 -C /usr/local/bin docker/docker
        echo
      fi
      cmd="echo 'export DOCKER_HOST=ssh://$GUESTUSER@master' >> ~/.profile && . ~/.profile"
      echo $cmd | pbcopy
      echo "exec to use docker on master (copied to clipboard):"
      echo
      echo $cmd
    ;;
    share)
      echo "1. make sure File Sharing is enabled on your Mac:"
      echo "  System Preferences -> Sharing -> "
      echo "       -> [x] File Sharing"
      echo "       -> Options..."
      echo "         -> [x] Share files and folders using SMB"
      echo "         -> Windows File Sharing: [x] Your Account"
      echo

      if sharing -l | grep hyperctl > /dev/null; then
        echo "2. (not setting up host $HOME -> /hyperctl share, already present...)"
        echo
      else
        echo "2. setting up host $HOME -> /hyperctl share..."
        echo
        cmd="sudo sharing -a $HOME -s 001 -g 000 -n hyperctl"
        echo $cmd
        echo
        $cmd
        echo
      fi

      cmd="sudo mkdir -p $HOME && sudo mount -t cifs //$CIDR.1/hyperctl $HOME -o sec=ntlm,username=$GUESTUSER,vers=3.0,sec=ntlmv2,noperm"
      echo $cmd | pbcopy
      echo "3. "$cmd
      echo "  ^ copied to the clipboard, paste & execute on master:"
      echo "    (just press CMD+V, <enter your Mac password>, ENTER, CTRL+D)"
      echo
      ssh $SSHOPTS $GUESTUSER@master

      echo
      cmd="docker run -it -v $PWD:$PWD r-base ls -l $PWD"
      echo $cmd | pbcopy
      echo "4. "$cmd
      echo "  ^ copied to the clipboard, paste & execute locally to test the sharing"
    ;;
    helm2)
      # (cover case when v2 brew was overwritten by v3 beta)
      if ! helm version 2> /dev/null | head -n 1 | grep 'v2' > /dev/null; then
        brew reinstall kubernetes-helm
      fi

      helmdir="$HOME/.hyperhelm"
      hyperhelm="helm --kubeconfig $HOME/.kube/config.hyperctl --home $helmdir"

      if [ -a $helmdir ]; then
        echo
        echo "deleting previous $helmdir"
        echo
        rm -rf $helmdir
      fi

      echo
      $hyperctl --namespace kube-system create serviceaccount tiller
      $hyperctl create clusterrolebinding tiller --clusterrole cluster-admin \
        --serviceaccount=kube-system:tiller
      $hyperhelm init --service-account tiller

      echo
      sleep 5
      $hyperctl get pods --field-selector=spec.serviceAccountName=tiller --all-namespaces

      echo
      echo "to setup bash alias, exec:"
      echo
      echo "echo \"alias hyperhelm='$hyperhelm'\" >> ~/.profile"
      echo "source ~/.profile"
    ;;
    helm3)
      helmzip=$WORKDIR/$(basename $HELMURL)
      if ! [ -a $helmzip ]; then
        curl -L $HELMURL -o $helmzip
      fi
      tar zxf $helmzip -C /usr/local/bin --strip 1 darwin-amd64/helm
      echo
      echo "helm version: $(helm version)"

      hyperhelm="helm --kubeconfig $HOME/.kube/config.hyperctl"

      echo
      echo "to setup bash alias, exec:"
      echo
      echo "echo \"alias hyperhelm='$hyperhelm'\" >> ~/.profile"
      echo "source ~/.profile"
    ;;
    repo)
      # add remote helm repo
      hyperhelm repo add stable https://kubernetes-charts.storage.googleapis.com
      hyperhelm repo update

      # prepare secrets for local repo
      certs=$WORKDIR/certs
      mkdir -p $certs
      openssl req -newkey rsa:4096 -nodes -sha256 -subj "/C=/ST=/L=/O=/CN=master" \
        -keyout $certs/tls.key -x509 -days 365 -out $certs/tls.cert
      hyperctl create secret tls master --cert=$certs/tls.cert --key=$certs/tls.key

      # distribute certs to our nodes
      allnodes=( $(get-all-nodes) )
      for node in ${allnodes[@]}; do
        scp $SSHOPTS $certs/tls.cert $GUESTUSER@$node:
        ssh $SSHOPTS $GUESTUSER@$node sudo mkdir -p /etc/docker/certs.d/master:30699/
        ssh $SSHOPTS $GUESTUSER@$node sudo mv tls.cert /etc/docker/certs.d/master:30699/ca.crt
      done

      # launch local repo on master
      hyperhelm install registry stable/docker-registry \
        --set tolerations[0].key=node-role.kubernetes.io/master \
        --set tolerations[0].operator=Exists \
        --set tolerations[0].effect=NoSchedule \
        --set nodeSelector.kubernetes\\.io/hostname=master \
        --set tlsSecretName=master \
        --set service.type=NodePort \
        --set service.nodePort=30699

      print-local-repo-tips
    ;;
    iso)
      go-to-scriptdir
      write-user-data "${DISTRO}.yaml"
      echo "debug cloud-config was written to ./${DISTRO}.yaml"
    ;;
    help)
      help
    ;;
    *)
      echo "unknown command: $arg; try ./hyperctl.sh help"
    ;;
  esac
done

echo

go-to-scriptdir
