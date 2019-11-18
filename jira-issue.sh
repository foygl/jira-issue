#!/bin/bash

set -e

## User Configuration ##

EMAIL= # User email
API_TOKEN= # https://id.atlassian.com/manage/api-tokens
PROJECT_NAME= # See: https://myid.atlassian.net/secure/BrowseProjects.jspa
PROJECT_KEY= # See: https://myid.atlassian.net/secure/BrowseProjects.jspa
ORG_URL= # https://myid.atlassian.net

########################

SUMMARY="$1"
if [ ! "${SUMMARY}" ]
then
  echo "Usage: $0 \"SUMMARY\" \"DESCRIPTION (OPTIONAL)\""
  exit 1
fi

DESCRIPTION="$2"

########################

API_URL=${ORG_URL}/rest/api/3
AGILE_API_URL=${ORG_URL}/rest/agile/1.0

function jira {
  curl -s -XGET -H 'Accept: application/json' --basic -u ${EMAIL}:${API_TOKEN} ${API_URL}/${1} | jq '.'
}

function jira_post {
  curl -s -XPOST -H 'Accept: application/json' -H 'Content-Type: application/json' --basic -u ${EMAIL}:${API_TOKEN} ${API_URL}/${1} -d "${2}"
}

function jira_put {
  curl -s -XPUT -H 'Accept: application/json' -H 'Content-Type: application/json' --basic -u ${EMAIL}:${API_TOKEN} ${API_URL}/${1} -d "${2}"
}

function jira_agile {
  curl -s -XGET -H 'Accept: application/json' --basic -u ${EMAIL}:${API_TOKEN} ${AGILE_API_URL}/${1} | jq '.'
}

function jira_agile_post {
  curl -s -XPOST -H 'Content-Type: application/json' --basic -u ${EMAIL}:${API_TOKEN} ${AGILE_API_URL}/${1} -d "${2}"
}

PROJECT=$( jira project/${PROJECT_KEY} )

PROJECT_ID=$( jq '.id' <<< ${PROJECT} | sed 's/"//g' )

BOARD_ID=$( jira_agile board?name=${PROJECT_NAME} | jq '.values[] | select(.location.projectId=='${PROJECT_ID}') | .id' )

SPRINTS=$( jira_agile board/${BOARD_ID}/sprint?state=future )

COMPONENT_IDS=$( jq '.components[].id' <<< ${PROJECT} | sed 's/"//g' )
for component in ${COMPONENT_IDS}
do
  echo "${component} : $( jq '.components[] | select(.id=="'${component}'") | .name' <<< ${PROJECT} )"
done

read -e -p "Type the id(s) of the component (default: none): " selected_components

SELECTED_COMPONENTS=""
if [ "${selected_components}" ]
then
  for component in ${selected_components}
  do
    if [ ! "$( echo ${COMPONENT_IDS} | grep "\b${component}\b" )" ]
    then
      echo "Invalid component '${component}' selected"
      exit 1
    fi
    SELECTED_COMPONENTS="${SELECTED_COMPONENTS} { \"id\" : \"${component}\" },"
  done
  SELECTED_COMPONENTS="$( sed 's/,$//' <<< ${SELECTED_COMPONENTS} )"
fi

SPRINT_IDS=$( jq '.values[].id' <<< ${SPRINTS} )
for sprint in ${SPRINT_IDS}
do
  echo "${sprint} : $( jq '.values[] | select(.id=='${sprint}') | .name' <<< ${SPRINTS} )"
done

read -e -p "Type the id of the sprint (default: Backlog): " selected_sprint

if [ "${selected_sprint}" ]
then
  if [ ! "$( echo ${SPRINT_IDS} | grep "\b${selected_sprint}\b" )" ]
  then
    echo "Invalid sprint '${selected_sprint}' selected"
    exit 1
  fi
fi

CREATE_ISSUE_RESPONSE=$( jira_post issue '{ "fields": { "summary" : "'"${SUMMARY}"'", "issuetype" : { "id" : "10001" }, "components" : ['"${SELECTED_COMPONENTS}"'], "project" : { "id" : "'${PROJECT_ID}'" }, "description" : { "type": "doc", "version": 1, "content": [ { "type": "paragraph", "content": [ { "text": "'"${DESCRIPTION}"'", "type": "text" } ] } ] } } }' )
ISSUE_ID=$( echo "${CREATE_ISSUE_RESPONSE}" | jq '.id' | sed 's/"//g' )

if [ "${ISSUE_ID}" == "null" ]
then
  echo "Issue not successfully created"
  echo "${CREATE_ISSUE_RESPONSE}" | jq '.'
  exit 1
fi

jira_put issue/${ISSUE_ID}/assignee '{ "accountId" : null }' > /dev/null

if [ "${selected_sprint}" ]
then
  jira_agile_post sprint/${selected_sprint}/issue '{ "issues" : [ "'${ISSUE_ID}'" ] }'
fi

echo "Issue created: ${ORG_URL}/browse/$( echo "${CREATE_ISSUE_RESPONSE}" | jq '.key' | sed 's/"//g' )"
