# SonarQube Housekeeping

Action that will remove projects matching a specific prefix from SonarQube 
that contains a Jira project issue that is not present in the git remote heads

The community edition of SonarQube doesn't support branch builds without 
the community plugin. Without this being available we have configured our
pipeline to alter the project key and project name on branch builds.
However we need to detect when the branch versions of projects are no longer
required and remove them. To do this we run a daily job to request the remote 
heads and the SonarQube projects and cross reference them to determine what
needs to be remove.

## Background
This requirement came from a project that doesn't use GitHub actions and was
running on a specifc linux based image with specific tools. A bash script 
was already written for the project that we wished to make more accessible and 
reusable. We decided that by placing the script into a docker image we 
could make the action more portable, including providing it as a GitHub action
and Harness Drone plugin.

## Inputs

| Input            | Description        | Required |
| ---------------- | ------------------ | -------- |
| sonarqube-host            | The URL of the SonarQube instance.            | Yes |
| sonarqube-token           | A token for accessing the SonarQube instance. | Yes |
| sonarqube-project-prefix  | The prefix used in the SonarQube project key  | Yes |
| jira-project-key          | The Jira project key                          | Yes |

## GitHub example

```yaml
steps:
    - name: SonarQube housekeeping
      uses: quay.io/ukhomeofficedigital/cicd-actions-sonarqube-housekeeping@v1
      with:
        sonarqube-host: 'https://sonarcloud.io/'
        sonarqube-token:  ${{ secrets.token }}
        sonarqube-project-prefix: 'myproject-api'
        jira-project-key: 'UKHO'
```

## Drone example

```yaml
kind: pipeline
type: docker
name: default

steps:
- name: SonarQube housekeeping
  image: quay.io/ukhomeofficedigital/cicd-actions-sonarqube-housekeeping@v1
  settings:
    sonarqube_host: 'https://sonarcloud.io/'
    sonarqube_token: 'dcfc5c44be894bb5b41f1be7fa60b4fc'
    sonarqube_project_prefix: 'myproject-api'
    jira_project_key: 'UKHO'

```