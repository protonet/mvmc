# Master VM Controller

A small [Sinatra][sinatra] app for managing [QEMU][qemu] VMs remotely or via
an SSH tunnel.

It doesn't use any Ruby/libvirt bindings, and talks directly to the shell.
That is both good and bad, but we have our reasons!

## Installation

You'll need Ruby `1.9.3-p194` or greater, it was built against Ruby `2.0.0-p0.

    $ git clone https://github.com/protonet/mvmc protonet-mvmc
    $ cd protonet-mvmc
    $ bundle

## Starting

It's easiest just to start it with Rackup

    $ rackup

It'll be started on port `:9292`.

## Setting Up

In order to use the remote control you'll need to have the `nodessh` wrapper,
and a user on the box that can use `sudo` to call `virt-install` and `virsh`
without asking for a password.

These commands might help, first the `nodessh` alias for your dotfiles:

    alias nodessh='ssh -o "ProxyCommand nc -X connect -x ssh.protonet.info:8022 %h %p" -o "User protonet"'

And second the `sudoers.d` entries for your user on the node:

    echo "protonet ALL=NOPASSWD:/usr/bin//usr/bin/virsh" >
    /etc/profile.d/protonet_passwordless_virsh

    echo "protonet ALL=NOPASSWD:/usr/bin//usr/bin/virt-install" >
    /etc/profile.d/protonet_passwordless_virt-install

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
