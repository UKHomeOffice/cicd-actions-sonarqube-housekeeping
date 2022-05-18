FROM alpine/git:v2.34.2
RUN apk add --no-cache bash curl jq

RUN adduser -u 2001 -D appuser appuser
USER appuser

COPY sonarqube.sh /usr/bin/sonarqube.sh

ENTRYPOINT ["bash", "/usr/bin/sonarqube.sh"]
