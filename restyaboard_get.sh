#!/bin/bash
# Download Restyaboard boards
# https://blog.sleeplessbeastie.eu/2018/04/02/how-to-backup-and-restore-restyaboard-boards/

# current date and time
current_datetime="$(date +%Y%m%d_%H%M%S)"

# usage info
usage(){
  echo "Usage:"
  echo "  $0 -r restyaboard_url -u username -p passsword [-b board_id|-t]"
  echo ""
  echo "Parameters:"
  echo "  -r restyaboard_url : set Restyaboard URL (required)"
  echo "  -u username        : set username (required)"
  echo "  -p password        : set password (required)"
  echo "  -b board_id        : set board id (optional)"
  echo "  -t                 : add timestamp to output filename (optional)"
  echo ""
}

# parse parameters
while getopts "r:u:p:b:t" option; do
  case $option in
    "r")
      param_board_address="${OPTARG}"
      param_board_address_defined=true
      ;;
    "u")
      param_username="${OPTARG}"
      param_username_defined=true
      ;;
    "p")
      param_password="${OPTARG}"
      param_password_defined=true
      ;;
    "b")
      param_board_id="${OPTARG}"
      param_board_id_defined=true
      ;;
    "t")
      param_date_prefix=true
      ;;
    \?|:|*)
      usage
      exit
      ;;
  esac
done

if [ "${param_board_address_defined}" = true ] && \
   [ "${param_username_defined}"      = true ] && \
   [ "${param_password_defined}"      = true ]; then

  # get access token
  access_token=$(curl --silent -X GET --header "Accept: application/json" "${param_board_address}/api/v1/oauth.json" | jq -r .access_token)
  if [ "${access_token}" == "" ]; then echo "Error connectiong to ${board_address}"; exit 1; fi

  # log in and use assign new access token
  access_token=$(curl --silent -X POST --header "Content-Type: application/json" --header "Accept: application/json" \
                      -d "{ \"email\": \"${param_username}\", \"password\": \"${param_password}\" }" \
                      "${param_board_address}/api/v1/users/login.json?token=${access_token}" | \
                 jq -r .access_token)
  if [ "${access_token}" == "" ]; then echo "Incorrect credentials"; exit 2; fi

  # define board IDs to dowload
  if [ "${param_board_id_defined}" = true ]; then
    board_ids="${param_board_id}"
  else
    board_ids=$(curl --silent -X GET --header "Accept: application/json" "${param_board_address}/api/v1/users/2/boards.json?token=${access_token}" | jq -r .user_boards[].board_id)
  fi
  if [ "${board_ids}" == "" ]; then echo "Board list is empty"; exit 4; fi

  # download boards
  for board_id in ${board_ids}; do
    if [ "${param_date_prefix}" = true ]; then
      filename="${board_id}-${current_datetime}.json"
    else
      filename="${board_id}.json"
    fi
    result=$(curl --silent --output - -X GET --header "Accept: application/json" "${param_board_address}/api/v1/boards/${board_id}.json?token=${access_token}" | jq -r 'select(.error != null) | .error | ("type \"\(.type)\" message \"\(.message)\"")')
    if [ -n "${result}" ]; then
      echo "There was an error ${result} when downloading board ID ${board_id}. Skipping."
    else
      curl --silent --output ${filename} -X GET --header "Accept: application/json" "${param_board_address}/api/v1/boards/${board_id}.json?token=${access_token}"
      board_name=$(jq '.name' ${filename})
      echo "Downloaded board ID ${board_id} with name ${board_name} to file \"${filename}\""
    fi
  done
else
  usage
fi

