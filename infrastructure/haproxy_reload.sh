#!/bin/bash

#:80/443
http=0
#:81
stats=1
chain="HAPROXY"

DPORT=80
[ ${chain}_SSL} == "true" ] && DPORT=443

port_prefix=855			    

preconfigure() {
  iptables -w -t nat -N ${chain}
  iptables -w -t nat -A PREROUTING -j ${chain}
  iptables -w -t nat -A OUTPUT -j ${chain}
  instance_prefix="${port_prefix}"
  http_port="${instance_prefix}${http}"
  stats_port="${instance_prefix}${stats}"
  
  [ ${LISTEN_IP} != "0.0.0.0" ] && \
      iptables -w -t nat -A ${chain} -p tcp -d ${LISTEN_IP} --dport ${DPORT} -j DNAT --to-destination ${LISTEN_IP}:${http_port}
  iptables -w -t nat -A ${chain} -m state --state NEW -p tcp -d ${HOST_IP} --dport ${DPORT} -j REDIRECT --to ${http_port}
  iptables -w -t nat -A ${chain} -m state --state NEW -p tcp -d ${HOST_IP} --dport 81 -j REDIRECT --to ${stats_port}
}

configure() {
  instance=$1
  instance_prefix="${port_prefix}"
  http_port="${port_prefix}${http}"
  stats_port="${port_prefix}${stats}"
  export PORT_STATS=${stats_port}
  export PORT_HTTP=${http_port}
  eval "$(cat /etc/haproxy/haproxy.cfg| sed 's/^\(.*\)/echo "\1"/')" >| /etc/haproxy/$1.cfg
  /usr/sbin/$1 -c -f /etc/haproxy/$1.cfg
}

# Race condition can happen also here
# but any mutex (flock/mkdir) here slows down and add additional complexity
# it doesn't matter here which one start faster,
# since we retry evey fail start
#
service_restart() {
  configure $1 || { echo "[ERROR] - configruation file is broken - leaving state as it is"; exit 0; }
  /usr/sbin/$1 -p /tmp/$1.pid -f /etc/haproxy/$1.cfg -sf $(pidof $1)
}

remove() {
  while iptables -w -t nat -D PREROUTING -j ${chain} > /dev/null 2>&1; do echo "remove from PREROUTING ${chain}"; done
  while iptables -w -t nat -D OUTPUT -j ${chain} > /dev/null 2>&1; do echo "remove from OUTPUT ${chain}"; done
  while iptables -w -t nat -D ${chain} 1 >/dev/null 2>&1; do echo "remove from: ${chain}"; done
  while iptables -w -t nat -X ${chain} >/dev/null 2>&1; do echo "remove ${chain}"; done
  return 0
}

init() {
  echo "Initiating routing"
  remove
  preconfigure
  service_restart haproxy
}

main() {
  if [[ $1 == "cleanup" ]]; then
      remove
      exit 0
  fi
  init
}

main $1

