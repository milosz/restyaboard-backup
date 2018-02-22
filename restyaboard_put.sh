#!/bin/bash
# Upload and restore Restyaboard board
# https://blog.sleeplessbeastie.eu/2018/04/02/how-to-backup-and-restore-restyaboard-boards/

# usage info
usage(){
  echo "Usage:"
  echo "  $0 -r restyaboard_url -u username -p passsword -f json_board_file"
  echo ""
  echo "Parameters:"
  echo "  -r restyaboard_url : set Restyaboard URL (required)"
  echo "  -u username        : set username (required)"
  echo "  -p password        : set password (required)"
  echo "  -f JSON file       : exported JSON board (optional)"
  echo ""
}

# parse parameters
while getopts "r:u:p:f:" option; do
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
    "f")
      param_file="${OPTARG}"
      param_file_defined=true
      ;;
    \?|:|*)
      usage
      exit
      ;;
  esac
done

if [ "${param_board_address_defined}" = true ] && \
   [ "${param_username_defined}"      = true ] && \
   [ "${param_password_defined}"      = true ] && \
   [ "${param_file_defined}"          = true ] && \
   [ -f "${param_file}"                      ]; then

  # get access token
  access_token=$(curl --silent -X GET --header "Accept: application/json" "${param_board_address}/api/v1/oauth.json" | \
                 jq -r .access_token)
  if [ -z "${access_token}" ]; then echo "Error connectiong to ${board_address}"; exit 1; fi

  # log in and use assign new access token
  access_token=$(curl --silent -X POST --header "Content-Type: application/json" --header "Accept: application/json" \
                      -d "{ \"email\": \"${param_username}\", \"password\": \"${param_password}\" }" \
                      "${param_board_address}/api/v1/users/login.json?token=${access_token}" | \
                 jq -r .access_token)
  if [ -z "${access_token}" ]; then echo "Incorrect credentials"; exit 2; fi

  # get user ID
  user_id=$(curl --silent -X GET --header "Accept: application/json" "${param_board_address}/api/v1/users/me.json?token=${access_token}" | \
            jq -r .id)
  if [ -z "${user_id}" ]; then echo "Cannot get user id"; exit 3; fi

  # read basic board paramters: id, name and background color
  # board_visibility will be deliberately set to 0
  board_name=$(jq -r .name ${param_file})
  board_id=$(jq -r .id ${param_file})
  board_background_color=$(jq -r 'select(.background_color != null) | .background_color' ${param_file})
  if [ -z "${board_name}" ] || [ -z "${board_id}" ]; then echo "Board name or id is not defined"; exit 4; fi

  new_board_id=$(curl --silent \
                       -X POST \
                      --header 'Content-Type: application/json' \
                      --header 'Accept: application/json' \
                       -d '{
                             "board_visibility": 0,
                             "name": "'"${board_name}"'",
                             "user_id": '${user_id}',
                             "background_color": "'${board_background_color}'"
                           }' \
                      "${param_board_address}/api/v1/boards.json?token=${access_token}" | \
                 jq -r '.id')

  echo "Created board \"${board_name}\" - ${param_board_address}/#/board/${new_board_id}"

  # parse and create lists
  for list_id in $(jq -r .lists[].id ${param_file}); do
    # read basic list parameters: id, name, is_archived, position, color
    list_name=$(jq -r '.lists[] | select(.id == '${list_id}') | .name' ${param_file})
    list_is_archived=$(jq -r '.lists[] | select(.id == '${list_id}') | .is_archived' ${param_file})
    list_position=$(jq -r '.lists[] | select(.id == '${list_id}') | .position' ${param_file})
    list_color=$(jq -r '.lists[] | select(.id == '${list_id}') | select(.color != null) | .color' ${param_file})
    list_cards=$(jq -r '.lists[] | select(.id == '${list_id}') | select(.cards != null) | .cards[].id' ${param_file})

    new_list_id=$(curl --silent \
                        -X POST \
                       --header 'Content-Type: application/json' \
                       --header 'Accept: application/json' \
                        -d '{
                              "board_id": '${new_board_id}',
                              "name": "'"${list_name}"'",
                              "is_archived": '${list_is_archived}',
                              "position": '${list_position}',
                              "color": "'${list_color}'"
                            }' \
                       "${param_board_address}/api/v1/boards/${new_board_id}/lists.json?token=${access_token}" | \
                  jq -r '.id')

    echo " + Created list \"${list_name}\""

    # parse list cards
    if [ -n "${list_cards}" ]; then # 
      for card_id in ${list_cards}; do
        # read basic card parameters: id, name, description, position, color, is_archived, notification_due_date
        card_name=$(jq -r '.lists[] | select(.id == '${list_id}') | .cards[] | select(.id == '${card_id}') | .name' ${param_file})
        card_description=$(jq '.lists[] | select(.id == '${list_id}') | .cards[] | select(.id == '${card_id}') | select(.description != null) | .description' ${param_file})
        card_position=$(jq -r '.lists[] | select(.id == '${list_id}') | .cards[] | select(.id == '${card_id}') | .position ' ${param_file})
        card_color=$(jq -r '.lists[] | select(.id == '${list_id}') | .cards[] | select(.id == '${card_id}') | .color ' ${param_file})
        card_is_archived=$(jq -r '.lists[] | select(.id == '${list_id}') | .cards[] | select(.id == '${card_id}') | .is_archived ' ${param_file})
        card_notification_due_date=$(jq -r '.lists[] | select(.id == '${list_id}') | .cards[] | select(.id == '${card_id}') | select(.notification_due_date != null) |  .notification_due_date ' ${param_file})

        # fix empty description
        if [ -z "${card_description}" ]; then
          card_description='""'
        fi
      
        new_card_id=$(curl --silent -X POST \
                           --header 'Content-Type: application/json' \
                           --header 'Accept: application/json' \
                            -d '{
                                  "board_id": '${new_board_id}',
                                  "list_id": '${new_list_id}',
                                  "name": "'"${card_name}"'",
                                  "position": '${card_position}',
                                  "description": '"${card_description}"',
                                  "due_date": "'"${card_notification_due_date}"'",
                                  "color": "'"${card_color}"'",
                                  "is_archived": "'"${card_is_archived}"'"
                                }' \
                           "${param_board_address}/api/v1/boards/${new_board_id}/lists/${new_list_id}/cards.json?token=${access_token}" | \
                      jq -r '.id')

        echo "   - Added card \"${card_name}\"" 

        # parse labels
        # each label is a single word
        card_labels=$(jq -r '.lists[] | select(.id == '${list_id}') | .cards[] | select(.id == '${card_id}') | select(.cards_labels != null) | .cards_labels[].label_id' ${param_file})
        card_label_names="" # initialize empty variable as will send all labels in one api call
        if [ -n "${card_labels}" ]; then
          for card_label_id in $card_labels; do
            # read basic label parameters: id, name
            card_label_name=$(jq -r '.lists[] | select(.id == '${list_id}') | .cards[] | select(.id == '${card_id}') | .cards_labels[] | select(.label_id == '${card_label_id}') | .name' ${param_file})

            # join labels
            if [ -z "${card_label_names}" ]; then
              card_label_names=$(echo "${card_label_name}")
            else
              card_label_names=$(echo "${card_label_names},${card_label_name}")
            fi
          done

          new_card_label_id=$(curl --silent \
                                    -X POST \
                                   --header 'Content-Type: application/json' \
                                   --header 'Accept: application/json' \
                                    -d '{
                                          "board_id": '${new_board_id}',
                                          "list_id": '${new_list_id}',
                                          "card_id": '${new_card_id}',
                                          "name": "'"${card_label_names}"'"
                                        }' \
                                   "${param_board_address}/api/v1/boards/${new_board_id}/lists/${new_list_id}/cards/${new_card_id}/labels.json?token=${access_token}" | \
                              jq -r '.id')

          echo "     @${card_label_names}" | sed "s/,/, /g"
        fi

        # parse checklists
        card_checklists=$(jq -r '.lists[] | select(.id == '${list_id}') | .cards[] | select(.id == '${card_id}') | select(.cards_checklists != null) | .cards_checklists[].id' ${param_file})
        if [ -n "${card_checklists}" ]; then
          for card_checklist_id in $card_checklists; do
            # read basic checklist parameters: id, name, position
            card_checklist_name=$(jq -r '.lists[] | select(.id == '${list_id}') | .cards[] | select(.id == '${card_id}') | .cards_checklists[] | select(.id == '${card_checklist_id}') | .name' ${param_file})
            card_checklist_position=$(jq -r '.lists[] | select(.id == '${list_id}') | .cards[] | select(.id == '${card_id}') | .cards_checklists[] | select(.id == '${card_checklist_id}') | .position' ${param_file})

            new_card_checklist_id=$(curl --silent \
                                          -X POST \
                                         --header 'Content-Type: application/json' \
                                         --header 'Accept: application/json' \
                                          -d '{
                                                "board_id": '${new_board_id}',
                                                "list_id": '${new_list_id}',
                                                "card_id": '${new_card_id}',
                                                "position": '${card_checklist_position}',
                                                "name": "'"${card_checklist_name}"'"
                                              }' \
                                         "${param_board_address}/api/v1/boards/${new_board_id}/lists/${new_list_id}/cards/${new_card_id}/checklists.json?token=${access_token}"  | \
                                    jq -r '.id')

            echo "      + Checklist $card_checklist_name"

            # parse checklist item
            card_checklist_items=$(jq -r '.lists[] | select(.id == '${list_id}') | .cards[] | select(.id == '${card_id}') | .cards_checklists[] | select(.id == '${card_checklist_id}') | select(.checklists_items != null) | .checklists_items[].id' ${param_file})
            if [ -n "${card_checklist_items}" ]; then
              for card_checklist_item_id in ${card_checklist_items}; do
                # read basic checklist item parameters: id, name, is_completed, position
                card_checklist_item_name=$(jq -r '.lists[] | select(.id == '${list_id}') | .cards[] | select(.id == '${card_id}') | .cards_checklists[] | select(.id == '${card_checklist_id}') | .checklists_items[] | select(.id == '${card_checklist_item_id}') | .name' ${param_file})
                card_checklist_item_is_completed=$(jq -r '.lists[] | select(.id == '${list_id}') | .cards[] | select(.id == '${card_id}') | .cards_checklists[] | select(.id == '${card_checklist_id}') | .checklists_items[] | select(.id == '${card_checklist_item_id}') | .is_completed' ${param_file})
                card_checklist_item_position=$(jq -r '.lists[] | select(.id == '${list_id}') | .cards[] | select(.id == '${card_id}') | .cards_checklists[] | select(.id == '${card_checklist_id}') | .checklists_items[] | select(.id == '${card_checklist_item_id}') | .position' ${param_file})

                new_card_checklist_item_id=$(curl --silent \
                                                   -X POST \
                                                  --header 'Content-Type: application/json' \
                                                  --header 'Accept: application/json' \
                                                   -d '{
                                                         "board_id": '${new_board_id}',
                                                         "list_id": '${new_list_id}',
                                                         "card_id": '${new_card_id}',
                                                         "checklist_id": '${new_card_checklist_id}',
                                                         "is_completed": '${card_checklist_item_is_completed}',
                                                         "position": '${card_checklist_item_position}',
                                                         "name": "'"${card_checklist_item_name}"'"
                                                       }' \
                                                  "${param_board_address}/api/v1/boards/${new_board_id}/lists/${new_list_id}/cards/${new_card_id}/checklists/${new_card_checklist_id}/items.json?token=${access_token}"  | \
                                              jq -r '.id')

                echo "        - $card_checklist_item_name"
              done # checklist items
            fi # checklist items
          done # checklists
        fi # checklists
      done # cards
    fi # cards
  done # lists
else
  usage
fi
