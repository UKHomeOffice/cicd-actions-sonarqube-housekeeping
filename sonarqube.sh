#!/bin/bash

function sonarQubeApiRequest {

    # curl the solarqube request
    # add data if passed as an argument
    # as we want to validate the response code for some error handling
    # it needs to be written to the output so that it can be parsed and checked
    http_response=($(curl \
        -s --write-out "\n%{content_type}\n%{http_code}" \
        -X $1 \
        -u $sonarqubeToken: \
        -H 'ASccepts: application/json' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        ${3/*/-d} $3 \
        ${sonarqubeHost}$2 \
    ))

    # To support bash versions without support for negative indices
    # count the elements and subtract 1
    let minus_one=${#http_response[@]}-1
    # get the last element which we know includes the status code
    # because of the --write-out argument passed to curl 
    response_code=${http_response[minus_one]}

    # remove the status code from the output 
    # by removing the last element of the array
    unset 'http_response[${#http_response[@]}-1]'

    # check the response was successful
    if [[ $response_code -lt 200  || $response_code -ge 300 ]]; then
        printf "\nRequest for '${sonarqubeHost}$2' errored with response code $response_code\n\n" 1>&2
        exit 1
    fi

    # content-type needs to be checked because if anything is malformed
    # in the request it may return html and a successful code instead of json
    # this can't be done if no content is returned i.e. a 204 response
    if [ $response_code -ne 204 ];then
        # get the second to last element which we know includes the content type
        # but only when returning content
        let minus_one=${#http_response[@]}-1
        content_type=${http_response[minus_one]}

        unset 'http_response[${#http_response[@]}-1]'

        if [ $content_type != 'application/json' ]; then
            printf "\nRequest for '$2' errored as it returned an unexpected content-type\n\n" 1>&2
            exit 1
        fi
    fi

    # set the response variable so that it cab be used by the caller
    RESPONSE="${http_response[@]}"
}

# GitHub actions will pass arguments to the script but drone uses prefixed
# environment variables. Assign parameters to named variables
sonarqubeHost=$1$PLUGIN_SONARQUBE_HOST
sonarqubeToken=$2$PLUGIN_SONARQUBE_TOKEN
sonarqubeProjectPrefix=$3$PLUGIN_SONARQUBE_PROJECT_PREFIX
jiraProjectKey=$4$PLUGIN_JIRA_PROJECT_KEY

if [[ -z "$sonarqubeHost" || -z "$sonarqubeToken" || -z "$jiraProjectKey" || -z "$jiraProjectKey" ]]; then
    printf "\nIncorrect use. Please provide a SonarQube host, SonarQube token, a SonarQube project prefix and a Jira project key\n\n" 1>&2
    exit 1
fi;

# In Drone if DRONE_NETRC_PASSWORD is set then we need to config auth 
if [[ ! -z "$DRONE_NETRC_PASSWORD" ]]; then
    git config --global url."https://$DRONE_NETRC_USERNAME:$DRONE_NETRC_PASSWORD@$DRONE_NETRC_MACHINE".insteadof https://$DRONE_NETRC_MACHINE
fi;

git config --global --add safe.directory $(pwd)
# get the remote branches
branches=$(git ls-remote --heads -q)
# get the solar projects that start with the name of the relevant project and
# include a JIRA reference
sonarQubeApiRequest GET "api/components/search?q=$sonarqubeProjectPrefix-$jiraProjectKey&qualifiers=TRK"
projects_response=$RESPONSE

# branches are uppercased and split. the format from the git ls-remotes command means only every 
# other element contains a value we care about but the other are superfluous.
# From the SolarQube response we then match all components
# where the key doesn't match a branch.
# To match we strip the project name prefix which should leave us with just
# the jira issue.
#
# E.G. ls-remotes returns
#
# 8de2fe58e82858d995f9e099126e5d536445e848        refs/heads/master
# f6709d44563b855b4aeef46fb56f149056b5f453        refs/heads/task/EAHW-1863/Set-Up-Sonarqube
#
# this will be passed to jq as an array of 4 elements
# The SonarQube response returns
# {
#     "paging": {
#         "pageIndex": 1,
#         "pageSize": 100,
#         "total": 1
#     },
#     "components": [
#         {
#             "key": "Callisto-JpaRest-EAHW-1863",
#             "name": "Callisto-JpaRest-EAHW-1863",
#             "qualifier": "TRK",
#             "project": "Callisto-JpaRest-EAHW-1863"
#         },
#         {
#             "key": "JCallisto-paRest-EAHW-1864",
#             "name": "Callisto-JpaRest-EAHW-1864",
#             "qualifier": "TRK",
#             "project": "Callisto-JpaRest-EAHW-1864"
#         }
#     ]
# }
#
# The Callisto-JpaRest- prefix will be stripped from the keys and checked to see if it exists in the branches
# it will find EAHW-1863 in the remote branch refs/heads/task/EAHW-1863/Set-Up-Sonarqube
# but wont find a branch for Callisto-JpaRest-EAHW-1864
# therefore we will assume this project was for a branch that has been removed.
# It also checks that the project key isn't an exact match for the prefix because although
# the call to the search suffixes the project prefix with the jira project key we saw sometimes
# the results where questionable
jq_branches=${branches[@]@E} # Use shell parameter expansion with E operator to ensure the value is escaped before passing to jq
projects=($(echo "${projects_response}" | jq -r '($branches | ascii_upcase | split(" ")) as $currentBranches | .components[] | select((.key|ascii_upcase| gsub($sonarqubeProjectPrefix+"-";"";"i")) as $key | ( $key!=($sonarqubeProjectPrefix | ascii_upcase) and (any($currentBranches[]; contains($key)) | not)))| .key' --arg sonarqubeProjectPrefix "$sonarqubeProjectPrefix" --arg branches "$jq_branches"))


# Delete the SonarQube projects that no longer have branches
for projectKey in "${projects[@]}"
do
    echo Removing SonarQube project $projectKey
    content=project=$projectKey
    sonarQubeApiRequest POST "api/projects/delete" "$content"
done


