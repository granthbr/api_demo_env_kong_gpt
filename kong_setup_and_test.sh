#!/usr/bin/env bash

if ! hash jq &> /dev/null; then
  echo "command jq not found, please install jq to run this script..."
  exit 1
fi

METRICS_SERVICE_NAME="prometheusEndpoint"
METRICS_SERVICE_ROUTE_NAME="metrics"
METRICS_SERVICE_URL="http://kong-ee:8100/metrics"

SERVICE_NAMES=( "service1" "service2" "service3" "service4" "service5" )
ROUTE_NAMES=( "route1" "route2" "route3" "route4" "route5" )
USER_KEYS=( "1234" "12345" "123456" "1234567" "12345678" )
USERS=( "user1" "user2" "user3" "user4" "user5" )

SERVICE_HOST="httpbin.org"
TOKEN="kong"

KONG_ADMIN_API="http://127.0.0.1:8001"
KONG_PROXY="http://127.0.0.1:8000"
KONG_PROXY_HTTPS="https://127.0.0.1:443"
# WORKSPACE=${2:default}
ACTION=${1:-create}

function create_consumers() {

  INDEX=$1
  CONSUMER="${USERS[$INDEX]}"
  USER_KEY="${USER_KEYS[$INDEX]}"

  curl -s -X POST \
  ${KONG_ADMIN_API}/consumers/ \
  --data "username=${CONSUMER}"   | jq

  curl -s -X POST \
  --url ${KONG_ADMIN_API}/consumers/${CONSUMER}/key-auth/ \
  --data "key=${USER_KEY}"   | jq

  curl -s -X POST ${KONG_ADMIN_API}/consumers/${CONSUMER}/plugins/ \
    --data "name=file-log"  \
    --data "config.path=/dev/stdout" \
    --data "config.reopen=false"   | jq
}

function create_global_plugins() {

  curl -s -X POST ${KONG_ADMIN_API}/plugins/ \
    --data "name=prometheus"   | jq

  curl -s -X POST ${KONG_ADMIN_API}/services \
    --data "name=${METRICS_SERVICE_NAME}" \
    --data "url=${METRICS_SERVICE_URL}" \
      | jq

  curl -s -X POST ${KONG_ADMIN_API}/services/${METRICS_SERVICE_NAME}/routes \
    --data "name=${METRICS_SERVICE_ROUTE_NAME}" \
    --data "paths[]=/${METRICS_SERVICE_ROUTE_NAME}" \
      | jq
}

function create_services() {

INDEX=$1
SERVICE_NAME="${SERVICE_NAMES[$INDEX]}"
ROUTE_NAME="${ROUTE_NAMES[$INDEX]}"

  curl -s -X POST ${KONG_ADMIN_API}/services \
    --data "name=${SERVICE_NAME}" \
    --data "url=http://${SERVICE_HOST}/get"   | jq

  curl -s -X POST ${KONG_ADMIN_API}/services/${SERVICE_NAME}/plugins \
    --data "name=key-auth" \
    --data "config.key_names=apikey"  | jq

  curl -s -X POST ${KONG_ADMIN_API}/services/${SERVICE_NAME}/routes \
    --data "name=${ROUTE_NAME}" \
    --data "paths[]=/${ROUTE_NAME}"  | jq
}

function run_test() {
  INDEX=$1
  
  ROUTE_NAME="${ROUTE_NAMES[$INDEX]}"

  KEY_INDEX=$(( RANDOM % 5 ))
  API_KEY="${USER_KEYS[$KEY_INDEX]}"

curl -v -i -k ${KONG_PROXY}/${ROUTE_NAME}?apikey=${API_KEY}

  echo -e "\n"
}

function clean() {

  for i in {0..4}; do
    FL_ID=$(curl -s ${KONG_ADMIN_API}/consumers/${USERS[$i]}/plugins \
        | jq -r '.data[] | select(.name | contains("file-log"))| .id')
    curl -i -X DELETE -k ${KONG_ADMIN_API}/consumers/${USERS[$i]}/plugins/${FL_ID}  

    KA_ID=$(curl -s ${KONG_ADMIN_API}/consumers/${USERS[$i]}/plugins \
        |  jq -r '.data[] | select(.name | contains("key-auth"))| .id')
    curl -i -X DELETE -k ${KONG_ADMIN_API}/consumers/${USERS[$i]}/plugins/${KA_ID}  
  done

  FL_ID=$(curl -s ${KONG_ADMIN_API}/plugins \
      |  jq -r '.data[] | select(.name | contains("file-log"))| .id')
  curl -i -X DELETE -k ${KONG_ADMIN_API}/plugins/${FL_ID}  

  KA_ID=$(curl -s ${KONG_ADMIN_API}/plugins \
      |  jq -r '.data[] | select(.name | contains("key-auth"))| .id')
  
  curl -i -X DELETE -k ${KONG_ADMIN_API}/plugins/${KA_ID}  

  PROM_ID=$(curl -s ${KONG_ADMIN_API}/plugins \
      |  jq -r '.data[] | select(.name | contains("prometheus"))| .id')
  
  curl -i -X DELETE -k ${KONG_ADMIN_API}/plugins/${PROM_ID}  

  for i in {0..4}; do
    curl -i -X DELETE -k ${KONG_ADMIN_API}/consumers/${USERS[$i]}  
    curl -i -X DELETE -k ${KONG_ADMIN_API}/routes/${ROUTE_NAMES[$i]}  
    curl -i -X DELETE -k ${KONG_ADMIN_API}/services/${SERVICE_NAMES[$i]}  
  done

  curl -s -X DELETE ${KONG_ADMIN_API}/services/${METRICS_SERVICE_NAME}/routes/${METRICS_SERVICE_ROUTE_NAME} \
      | jq

  curl -s -X DELETE ${KONG_ADMIN_API}/services/${METRICS_SERVICE_NAME} \
      | jq

}

if [ "${ACTION}" == "create" ]; then
  create_global_plugins
  for i in {0..4};  do
    create_services $i
    create_consumers $i
  done
elif [ "${ACTION}" == "test" ]; then
  sleep 4
  for i in {0..499};  do
    index=$(( RANDOM % 5 ))
    run_test $index
  done
elif [ "${ACTION}" == "clean" ]; then
  clean  
fi