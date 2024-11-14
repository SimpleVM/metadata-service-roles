# Metadata Service Roles

This repository holds the recipes for creating debian packages that hold the features for the metadata services.

## Features and Function

### Userdata

#### SSH Keys

This package enables the virtual machines within the network of the metadata server to retrieve user data.
It synchronizes the public-keys retrieved from the metadata server with the authorized-keys set in a dedicated authorization file to enable ssh access for users who got added after the start of the machine. The settings in the sshd-config get adjusted accordingly.


## General information

### Version checking

All scripts used to retrieve information from the server are versioned, which also holds for the data issued by the metadata server itself.
The `check_version.sh` script is used in all scripts executed in the course of the installed services to ensure compatibility between the services and the data retrieved.  

## Deployment

The deployment is to be managed over the GitHub-Action this repository, which builds the packages and puts them to the apt-repositories.
The `simplevm-metadata-service` package acsts as the meta-package that installs the core package and all feature-specific packages at once.
The packages are made available on [apt.bi.denbi.de](apt.bi.denbi.de). 
The deployment can also be run by hand - the following description is based on packages for Ubuntu 22.04 (jammy).

### Manual deployment

#### Building the packages

Make sure to have `dpkg` installed on the system you use for building the packages to be able to run `dpkg-deb`.
First go to the `packages` directory and run the following commands.


```bash

dpkg-deb -b core core_22.04.deb
dpkg-dev -b feature_package_directory_1 feature_package_1_22.04.deb
...
dpkg-deb -b feature_package_directory_n feature_package_n_22.04.deb
dpkg-deb -b meta meta_22.04.deb
```

#### Moving built package to apt-repository machine

Copy each built package to the corresponding directory on the apt-repository machine, e.g. with `scp`:
Make sure that the corresponding key and host is set in your ssh-config or adjust the `scp`-command accordingly.

```bash
scp core_22.04.deb ... meta_22.04.deb aptdenbi:/home/ubuntu/simplevm_packages/22.04
```
Connect to the apt-repository machine for the further steps.

```bash
ssh aptdenbi
sudo -i
reprepro -b /var/www/repos/apt/jammy includedeb jammy /home/ubuntu/simplevm_packages/core_22.04.deb
```
You will be asked for the passphrase of the GPG-key that is used to sign the packages.
The credentials can be found on the CeBiTec-volume: `/prj/denbi_cloud/portal/apt-management/signing.txt`. The key for the connection to the apt-machine can be found in the same directory.
c
Now the package is available in the apt-repository. See here for an example of available packages in the `simplevm-metadata-service`-context: 
[https://apt.bi.denbi.de/repos/apt/jammy/pool/main/s/simplevm-metadata-service/](https://apt.bi.denbi.de/repos/apt/jammy/pool/main/s/simplevm-metadata-service/)

#### Manual installation on the machine of use

Add the repository-key to your keyring (this handling might be deprecated and should be adjusted in the future!) and the repository to the sources via `apt` and install the packages with the meta-package.

```bash
wget https://apt.bi.denbi.de/repo_key.key
sudo apt-key  add repo_key.key
sudo add-apt-repository https://apt.bi.denbi.de/repos/apt/jammy jammy main
sudo apt update

sudo apt install simplevm-metadata-service
```
Now the packages are available on the machine.