# Zabbix5-Export-custom-triggers

Tempplate tested and work in zabbix 5.0.X.  
Script for Oracle databse, but you can recreate for other DB 
For use script you need import two files (file in folder script)
export_custom_triggers.sh    
export_custom_triggers_list.sh
in your zabbix-server

In file
export_custom_triggers.sh 
you need change variables

sqlplus_client
zabbix_db
zabbix_server
log_path
main_folder
triggers_list

In file
export_custom_triggers_list.sh  
storage your manualy added triggers in format  
hostid:trigger  
example in repo  

For check when script crash you can export template
Template Custom triggers check.xml  
and add it for your zabbix-server.

Example backup  

Host: Test  
Description: Very bad  
Priority: high  
Expression: {test:testt.sum(15m)}=0  
RecoveryExpression: null  
Comments: Houston we have a problem  
  
--------------------------------------------------  
  
Host: Test2  
Description: Not bad?  
Priority: average  
Expression: {test2:testt.sum(5m)}=0  
RecoveryExpression: null  
Comments: Houston we need help  