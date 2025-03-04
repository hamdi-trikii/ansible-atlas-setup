<h1 align="left">1.Apache Atlas Installation with Ansible</h1>

###

<p align="left">This Ansible playbook automates the installation and configuration of Apache Atlas 2.4.0 on a single-node Ubuntu machine, integrated with an existing HBase 2.5.5 installation. It’s designed to run as the gadet user with sudo privileges, installing Atlas in /opt/apache-atlas-2.4.0/ and configuring it to use an external HBase instance while managing a local Solr instance.</p>

###

<h2 align="left">Run the Playbook</h2>

###

<p align="left">ansible-playbook install_atlas.yml -K  -vvv</p>

###


<h1 align="left">2.Hive Integration with Apache Atlas - Ansible Playbook</h1>

###

<p align="left">This Ansible playbook integrates Apache Hive 3.1.2 with Apache Atlas 2.4.0 on a single-node Ubuntu machine, enabling Hive to send metadata to Atlas via the Atlas Hive hook. It assumes Atlas is already installed at /opt/apache-atlas-2.4.0/ and Hive at /opt/apache-hive-3.1.2-bin/, running as the gadet user with sudo privileges.</p>

###

<h2 align="left">Run the Playbook</h2>

###

<p align="left">ansible-playbook hive_atlas_integration.yml -K -vvv</p>

###
