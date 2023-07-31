#!/bin/bash -l

sqlplus_client="/usr/lib/oracle/<version>/client<os arch>/bin/sqlplus"
zabbix_db="<db>"
zabbix_server="<server>"

query="$1"
log_path="<path>"
main_folder="<path>"
triggers_list="<path>/export_custom_triggers_list.sh"
ora_connect="$sqlplus_client -s zabbix/$(grep -i "^dbpassword" /etc/zabbix/zabbix_server.conf | cut -d "=" -f2)@$zabbix_db"
priority_mass=('not classified' 'information' 'warning' 'average' 'high' 'disaster')

function is_number {
  if [[ $1 =~ ^[0-9]+$ ]]
  then
    echo 1
  else
    echo 0
  fi
}

function set_human_function_view {
  human_view="$1"
  function_id=$(echo "$1" | grep -E -o "\{[0-9]{2,10}\}")
  for k in $(echo "$function_id")
  do
    k=$(echo "$k" | sed "s/{//g;s/}//g")
    check_functionid=$(is_number "$k")
    if [ "$check_functionid" -eq 0 ]
    then
      echo $(date +"%Y-%m-%d %H:%M:%S") "[ERROR] Hostid is not number: $hostid" >> $log_path
      continue
    fi
    function_info=$($ora_connect << EOF
    SET termout off
    SET serveroutput off
    SET feedback off
    SET colsep '-;-'
    SET lines 32766
    SET pagesize 0
    SET echo off
    SET linesize 7500
    SET newpage none
    SET verify off
    SET trimspool on

    select DISTINCT json_object (
    'HostName' is h.host,
    'Key' is t.key_,
    'Function' is f.Name,
    'Parameter' is f.PARAMETER
)
    from functions f, items t, hosts h where f.ITEMID=t.ITEMID and f.FUNCTIONID='$k' and t.HOSTID=h.HOSTID;
    quit;
EOF
)
    host_name=$(echo "$function_info" | jq -r '.HostName')
    key=$(echo "$function_info" | jq -r '.Key')
    function=$(echo "$function_info" | jq -r '.Function')
    parameter=$(echo "$function_info" | jq -r '.Parameter')
    if [ "$parameter" == "null" ]
    then
      parameter=''
    fi
    human_view=$(echo "$human_view" | sed "s/$k/${host_name}:${key}.${function}(${parameter})/g")
  done
  echo "$human_view"
}

count_active_zabbix_process=$(ps aux | grep zabbix_server | grep -c -v "grep ")

if [ $count_active_zabbix_process -eq 0 ]
then
  echo $(date +"%Y-%m-%d %H:%M:%S") "[INFO] Server is not active. Job didn't start" >> $log_path
  exit
fi

if [ "$query" == 'export_sql' ]
then
  i=0
  echo $(date +"%Y-%m-%d %H:%M:%S") "[INFO] Start export" >> $log_path
  while read line
  do
    hostid="$(echo "$line" | cut -d ';' -f1)"
    check_hostid=$(is_number "$hostid")
    if [ "$check_hostid" -eq 0 ]
    then
      echo $(date +"%Y-%m-%d %H:%M:%S") "[ERROR] Hostid is not number: $hostid" >> $log_path
      continue
    fi
    hostid_num="$(echo "$line" | cut -d ';' -f1)_${i}"
    search_pattern=$(echo "$line" | cut -d ';' -f2)
    echo $(date +"%Y-%m-%d %H:%M:%S") "Export host: $hostid" >> $log_path

    trigger_info=$($ora_connect << EOF
    SET termout off
    SET serveroutput off
    SET feedback off
    SET colsep '-;-'
    SET lines 32766
    SET pagesize 0
    SET echo off
    SET linesize 7500
    SET newpage none
    SET verify off
    SET trimspool on

    select DISTINCT json_object (
    'Host' is t1.NAME,
    'Description' is t4.DESCRIPTION,
    'Priority' is t4.PRIORITY,
    'Expression' is regexp_replace(translate(t4.EXPRESSION, chr(10) || chr(13) || chr(09), ' '),'[[:space:]]{1,8}',' '),
    'RecoveryExpression' is regexp_replace(translate(t4.RECOVERY_EXPRESSION, chr(10) || chr(13) || chr(09), ' '),'[[:space:]]{1,8}',' '),
    'Comments' is t4.COMMENTS
)
    from hosts t1, items t2, functions t3, triggers t4 where t1.HOSTID=t2.HOSTID and t2.ITEMID=t3.ITEMID and t3.TRIGGERID=t4.TRIGGERID and t1.HOSTID='$hostid' and t4.DESCRIPTION LIKE '%$search_pattern%';
    quit;
EOF
)
    if [ "$trigger_info" == "" ]
    then
      echo $(date +"%Y-%m-%d %H:%M:%S") "[ERROR] trigger_info is empty" >> $log_path
      continue
    fi

    echo "$trigger_info" | while read j
    do
      host=$(echo "$j" | jq -r '.Host' 2>/dev/null)
      if [ "$host" == ""  ]
      then
        echo $(date +"%Y-%m-%d %H:%M:%S") "[ERROR] host is empty" >> $log_path
        continue
      fi
      description=$(echo "$j" | jq -r '.Description' 2>/dev/null)
      if [ "$description" == ""  ]
      then
        echo $(date +"%Y-%m-%d %H:%M:%S") "[ERROR] description is empty" >> $log_path
        continue
      fi
      priority=${priority_mass[$(echo "$j" | jq -r '.Priority'  2>/dev/null)]}
      if [ "$priority" == ""  ]
      then
        echo $(date +"%Y-%m-%d %H:%M:%S") "[ERROR] priority is empty" >> $log_path
        continue
      fi
      expression=$(echo "$j" | jq -r '.Expression' 2>/dev/null)
      if [ "$expression" == ""  ]
      then
        echo $(date +"%Y-%m-%d %H:%M:%S") "[ERROR] expression is empty" >> $log_path
        continue
      fi
      expression=$(set_human_function_view "$expression")
      recovery_expression=$(echo "$j" | jq -r '.RecoveryExpression' 2>/dev/null)
      recovery_expression=$(set_human_function_view "$recovery_expression")
      comments=$(echo "$j" | jq -r '.Comments' 2>/dev/null)
      for i in $(echo "$comments" | grep -E -o "rn[1-9]\)")
      do
        i_num=$(echo $i | sed "s/rn//g")
        comments=$(echo "$comments" | sed "s/$i/\n$i_num/g")
      done
      echo -e "Host: $host\nDescription: $description\nPriority: $priority\nExpression: $expression\nRecoveryExpression: $recovery_expression\nComments: $comments"  >> ${main_folder}/backup_custom_triggers_$(date +"%Y-%m-%d")
      echo -e "\n--------------------------------------------------\n" >> ${main_folder}/backup_custom_triggers_$(date +"%Y-%m-%d")
    done
    let "i=$i+1"
  done < $triggers_list

  echo $(date +"%Y-%m-%d %H:%M:%S") "[INFO] Finish export" >> $log_path

  size=$(stat ${main_folder}/backup_custom_triggers_$(date +"%Y-%m-%d") -c "%s" 2>/dev/null)

  check_size=$(is_number "$size")
  if [ "$check_size" -eq 0 ]
  then
    echo $(date +"%Y-%m-%d %H:%M:%S") "[ERROR] size is not number: $size" >> $log_path
  else
    zabbix_sender -z $zabbix_server -s $zabbix_server -k size_backup_custom_triggers -o "$size" >> $log_path 2>&1
  fi

elif [ "$query" == 'count_triggers' ]
then
  total_count=0
  echo $(date +"%Y-%m-%d %H:%M:%S") "[INFO] Start check triggers" >> $log_path
  while read line
  do
    hostid=$(echo "$line" | cut -d ';' -f1)
    check_hostid=$(is_number "$hostid")
    if [ "$check_hostid" -eq 0 ]
    then
      echo $(date +"%Y-%m-%d %H:%M:%S") "[ERROR] Hostid is not number: $hostid" >> $log_path
      continue
    fi
    search_pattern=$(echo "$line" | cut -d ';' -f2)
    count=$($ora_connect << EOF
      set termout off
      set serveroutput off
      set feedback off
      set colsep ';'
      set lines 32760
      set pagesize 0
      set echo off
      set feedback off
      set linesize 32760
      SET newpage none
      SET verify off
      set trimspool on

      SELECT count(*) from items t1, functions t2, triggers t3 where t1.ITEMID=t2.ITEMID and t2.TRIGGERID=t3.TRIGGERID and t1.HOSTID='$hostid' and t3.DESCRIPTION LIKE '%$search_pattern%';
      quit;
EOF
)
  echo "$search_pattern:$count" >> $log_path
  let "total_count=$total_count + $count"
  done < $triggers_list
  echo $(date +"%Y-%m-%d %H:%M:%S") "Finish check triggers" >> $log_path
  echo $(date +"%Y-%m-%d %H:%M:%S") "Send total count to zabbix" >> $log_path
  zabbix_sender -z $zabbix_server -s $zabbix_server -k count_custom_triggers -o "$total_count" >> $log_path 2>&1

elif [ "$query" == 'archive_and_clean' ]
then
  echo $(date +"%Y-%m-%d %H:%M:%S") "[INFO] Start archive" >> $log_path
  find $main_folder -maxdepth 1 -name "*[0-9]" -ctime +1 -exec gzip {} \; >> $log_path 2>&1

  echo $(date +"%Y-%m-%d %H:%M:%S") "[INFO] Clean old files" >> $log_path
  list_for_clean=$(find $main_folder -maxdepth 1 -ctime +30)
  if [ -z "$list_for_clean" ]
  then
    echo $(date +"%Y-%m-%d %H:%M:%S") "[INFO] Nothing for clean" >> $log_path
  else
    for i in $(echo $list_for_clean)
    do
       rm -rfv $i >> $log_path
    done >> $log_path
  fi

fi