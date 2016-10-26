#!/bin/bash

if [ $# -ne 6 ]; then
    echo "usage: ./run-test.sh <vm-name> <vm-ip> <test-name> <start-state-name> <selenese-test-file> <firefox-instance>"
    exit 1
fi


#python="/usr/local/lib/python2.7.11/bin/python"
python="/usr/bin/python"
vm_name=$1
guest_ip=$2
base_url="http://${guest_ip}"
test_name=$3
start_state_name=$4
selenese_test_file=$5
firefox_instance=$6
mosgi_start_relative="./mosgi/src/run-mosgi.lisp"
vilanoo_start_relative="./vilanoo2/src/"
vilanoo_folder="${HOME}/.vilanoo/"
timestamp=`date '+%Y%m%d%k%M'`
db_postfix=".db"
log_postfix=".log"
vilanoo_listen_port=8080
vilanoo_db_path="${vilanoo_folder}${test_name}-${timestamp}-vilanoo${db_postfix}"
mosgi_db_path="${vilanoo_folder}${test_name}-${timestamp}-mosgi${db_postfix}"
vilanoo_log_path="${vilanoo_folder}${test_name}-${timestamp}-vilanoo${log_postfix}"
mosgi_log_path="${vilanoo_folder}${test_name}-${timestamp}-mosgi${log_postfix}"
db_dump_schema="./data/DBSchemaDump.sql"


#default values for bitnami but else these need to become variables
inter_com_port=8844

mosgi_php_session_folder="/opt/bitnami/php/tmp/"
mosgi_xdebug_trace_file="/tmp/xdebug.xt"
mosgi_listen_interface="127.0.0.1"
mosgi_root_user="root"
mosgi_root_pwd="bitnami"


#check if vm is already running
#yes -> error
#no  -> restore virgin snapshot
if vboxmanage list vms | grep --quiet "\"${vm_name}\""; then
    
    if vboxmanage list runningvms | grep --quiet "\"${vm_name}\""; then
	echo "test vm ${vm_name} is currently running - shut down before trying again with using die .vdi and polesno.sh"
	exit 1
    else
	echo `vboxmanage snapshot ${vm_name} restore ${start_state_name}`
	echo `vboxmanage startvm ${vm_name}`
    fi
    
else
    echo "machine ${vm_name} is unknown"
    exit 1
fi


#setup mosgi_db_path
cat ${db_dump_schema} | sqlite3 ${mosgi_db_path}


#start vm"
echo "waiting for guest to finish starting up..."
sleep 2


tmux new -s ${start_state_name} "sbcl --dynamic-space-size 10000 --noinform --non-interactive --load ${mosgi_start_relative} -P ${mosgi_php_session_folder} -x ${mosgi_xdebug_trace_file} -p ${inter_com_port} -i ${mosgi_listen_interface} -t ${guest_ip} -r ${mosgi_root_user}  -c ${mosgi_root_pwd} -s ${mosgi_db_path} > >(tee ${mosgi_log_path}) 2> >(tee ${mosgi_log_path}); sleep 10" \; \
                                 split-window -h "sleep 8 ; cd ${vilanoo_start_relative}; ${python} vilanoo2.py -w 5 -p ${vilanoo_listen_port} -P ${inter_com_port} -s ${vilanoo_db_path} -S ${selenese_test_file} --selenese-args \"--firefox ${firefox_instance} --baseurl ${base_url} --height 2048 --width 1024\" > >(tee ${vilanoo_log_path}) 2> >(tee ${vilanoo_log_path}); sleep 30" \; attach \;




