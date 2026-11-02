#!/usr/bin/env bash
# Configure par l'API Zabbix l'enregistrement automatique des machines :
# un agent qui se présente avec HostMetadata "windows" (ou "linux") est créé, rangé dans son groupe
# et reçoit le modèle adapté — aucun ajout manuel d'hôte.
#   ZBX_URL=http://10.0.10.21/zabbix ZBX_USER=Admin ZBX_PASSWORD='…' ./zabbix-autoregistration.sh
set -euo pipefail

ZBX_URL="${ZBX_URL:-http://localhost/zabbix}"
API="${ZBX_URL%/}/api_jsonrpc.php"
ZBX_USER="${ZBX_USER:-Admin}"
: "${ZBX_PASSWORD:?Définir ZBX_PASSWORD}"
TOKEN=""

# call MÉTHODE JSON_PARAMS  → affiche .result (échoue si l'API renvoie une erreur)
call() {
  local body auth=()
  body=$(jq -nc --arg m "$1" --argjson p "$2" '{jsonrpc:"2.0", method:$m, params:$p, id:1}')
  [[ -n "$TOKEN" ]] && auth=(-H "Authorization: Bearer $TOKEN")
  local res
  res=$(curl -sf -H 'Content-Type: application/json-rpc' "${auth[@]}" -d "$body" "$API")
  if jq -e '.error' >/dev/null <<<"$res"; then
    echo "Erreur API ($1) : $(jq -r '.error.data' <<<"$res")" >&2
    exit 1
  fi
  jq -c '.result' <<<"$res"
}

TOKEN=$(call user.login "$(jq -nc --arg u "$ZBX_USER" --arg p "$ZBX_PASSWORD" '{username:$u, password:$p}')" | jq -r .)

group_id() { # crée le groupe d'hôtes s'il n'existe pas
  local id
  id=$(call hostgroup.get "$(jq -nc --arg n "$1" '{filter:{name:[$n]}}')" | jq -r '.[0].groupid // empty')
  [[ -z "$id" ]] && id=$(call hostgroup.create "$(jq -nc --arg n "$1" '{name:$n}')" | jq -r '.groupids[0]')
  echo "$id"
}
template_id() {
  call template.get "$(jq -nc --arg n "$1" '{filter:{host:[$n]}}')" | jq -r '.[0].templateid'
}

# register NOM_ACTION METADATA GROUPE MODELE
register() {
  local name=$1 meta=$2 gid tid exists params
  gid=$(group_id "$3")
  tid=$(template_id "$4")
  exists=$(call action.get "$(jq -nc --arg n "$name" '{filter:{name:[$n]}}')" | jq 'length')
  if [[ "$exists" -gt 0 ]]; then echo "= action « $name » déjà présente"; return; fi
  params=$(jq -nc --arg n "$name" --arg m "$meta" --arg g "$gid" --arg t "$tid" '{
    name: $n, eventsource: 2, status: 0,
    filter: { evaltype: 0, conditions: [ { conditiontype: 24, operator: 2, value: $m } ] },
    operations: [
      { operationtype: 2 },
      { operationtype: 4, opgroup: [ { groupid: $g } ] },
      { operationtype: 6, optemplate: [ { templateid: $t } ] }
    ] }')
  call action.create "$params" >/dev/null
  echo "+ action « $name » créée ($3, $4)"
}

register "Auto-enregistrement Windows" "windows" "Postes et serveurs Windows" "Windows by Zabbix agent active"
register "Auto-enregistrement Linux"   "linux"   "Serveurs Linux"            "Linux by Zabbix agent active"

call user.logout '[]' >/dev/null
