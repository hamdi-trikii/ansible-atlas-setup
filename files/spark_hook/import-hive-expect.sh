#!/usr/bin/expect -f
puts "🚨 DEBUG: ARGV = $argv"
puts "🚨 DEBUG: ARGC = $argc"

log_user 1
spawn /opt/apache-atlas-2.4.0/hook-bin/import-hive.sh

expect {
  "Enter username for atlas :-" {
    send "admin\r"
    exp_continue
  }
  "Enter password for atlas :-" {
    send "admin\r"
    exp_continue
  }
  eof
}
sleep 5
expect eof

