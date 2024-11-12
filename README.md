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