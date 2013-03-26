# Master VM Controller

A small [Sinatra][sinatra] app for managing [QEMU][qemu] VMs remotely or via
an SSH tunnel.

It doesn't use any Ruby/libvirt bindings, and talks directly to the shell.
That is both good and bad, but we have our reasons!

## Installation

You'll need the `libvirt-dev` package for your platform, as well as `libvirt``
and `virsh`:

    # apt-get install -y libvirt-dev libvirt virsh
    # apt-get install -y

You'll also need Ruby `1.9.3-p194` or greater, it was built against Ruby
`2.0.0-p0.

    $ git clone https://github.com/protonet/mvmc protonet-mvmc
    $ cd protonet-mvmc
    $ protonet_bundle

## Starting

It's easiest just to start it with Rackup

    $ rackup

It'll be started on port `:9292`.

## Setting Up

In order to use the remote control you'll need to have the access to the cebit
node without a password prompt (use ssh keys) and a user on the box that can
use `sudo` to call `virt-install` and `virsh` without asking for a password.

The `sudoers.d` entries for your user on the node:

    sudo echo "protonet ALL=NOPASSWD:/usr/bin/virsh"        > /etc/sudoers.d/protonet_passwordless_virsh
    sudo echo "protonet ALL=NOPASSWD:/usr/bin/virt-install" > /etc/sudoers.d/protonet_passwordless_virt-install
    sudo echo "protonet ALL=NOPASSWD:/bin/qemu-img"         > /etc/sudoers.d/protonet_passwordless_qemu-img
    sudo chmod 0400 /etc/sudoers.d/*

## Usage

You will almost certainly want to download the *libvirt* Windows drivers, the
ISO can be downloaded from:

 * http://alt.fedoraproject.org/pub/alt/virtio-win/latest/images/bin/virtio-win-0.1-52.iso

It must simply be uploaded along with all the other ISOs, where it should be
chosen as the "CD ISO" image in order that the Windows host can have access to
some driver image in order that the Windows host can have access to some
drivers.

## Test

There are some (unfinished) tests for checking the output of Virsh, they're a
WIP.

    $ rake test

## Configuring

VMs are always started with 50Gb of sparsely populated HDD space, 4GB of RAM,
and 2 virtual CPUs.

---
[sinatra]: www.example.com
[qemu]: www.example.com
