FROM alpine:3.20

RUN apk add --no-cache bash ca-certificates coreutils gzip minio-client postgresql16-client tar tzdata \
  && ln -sf /usr/bin/mcli /usr/local/bin/mc

COPY backup/backup.sh /usr/local/bin/domly-backup
COPY backup/restore.sh /usr/local/bin/domly-restore
RUN chmod +x /usr/local/bin/domly-backup /usr/local/bin/domly-restore

CMD ["domly-backup"]
