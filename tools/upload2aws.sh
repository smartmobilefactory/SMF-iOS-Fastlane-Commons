#!/bin/bash
#
# Upload a file to S3 AWS bucket
# Note: the bucket has to exist already
#
# (c) Smart Mobile Factory GmbH
#
# 07.09.2018

PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH
export PATH

#
# Helper
#

function usage() {
        echo "Upload file to S3 AWS bucket"
        echo
        echo "Required parameters:"
        echo -e "--bucket, -b\t\t: Bucket name"
        echo -e "--directory, -d\t\t: Directory under which to save the file in the bucket"
        echo -e "--file, -f\t\t: Path to file"
        echo -e "--accesskey, -a\t\t: S3 Access Key"
        echo -e "--secretkey, -s\t\t: S3 Secret Access Key"
        echo
        exit 0
}

#
# Variables
#

BUCKET=""
DIRECTORY=""
FILE=""
ACCESS_KEY=""
SECRET_KEY=""

#
# Arguments Loop
#

while [ $# -gt 0 ]; do
        case "$1" in
                --bucket | -b) 
                        BUCKET="$2"
                        shift 2
                        ;;  
                --directory | -d) 
                        DIRECTORY="$2"
                        shift 2
                        ;;  
                --file | -f)
                        FILE="$2"
                        shift 2
                        ;;  
                --accesskey | -a) 
                        ACCESS_KEY="$2"
                        shift 2
                        ;;  
                --secretkey | -s) 
                        SECRET_KEY="$2"
                        shift 2
                        ;;  
                -*) 
                        usage
                        ;;  
                *)  
        esac
done

#
# Main
#

if [ -z $BUCKET ] || [ -z $FILE ] || [ -z $ACCESS_KEY ] || [ -z $SECRET_KEY ]; then
        usage
fi

if [ ! -z $DIRECTORY ]; then
	DIRECTORY="/${DIRECTORY}"
fi

region="eu-central-1"
timestamp=$(date -u "+%Y-%m-%d %H:%M:%S")
signed_headers="date;host;x-amz-acl;x-amz-content-sha256;x-amz-date"
iso_timestamp=$(date -ujf "%Y-%m-%d %H:%M:%S" "${timestamp}" "+%Y%m%dT%H%M%SZ")
date_scope=$(date -ujf "%Y-%m-%d %H:%M:%S" "${timestamp}" "+%Y%m%d")
date_header=$(date -ujf "%Y-%m-%d %H:%M:%S" "${timestamp}" "+%a, %d %h %Y %T %Z")
file_basename=$(basename ${FILE})

payload_hash() {
  local output=$(shasum -ba 256 "$FILE")
  echo "${output%% *}"
}

canonical_request() {
  echo "PUT"
  echo "${DIRECTORY}/${file_basename}"
  echo ""
  echo "date:${date_header}"
  echo "host:${BUCKET}.s3.amazonaws.com"
  echo "x-amz-acl:public-read"
  echo "x-amz-content-sha256:$(payload_hash)"
  echo "x-amz-date:${iso_timestamp}"
  echo ""
  echo "${signed_headers}"
  printf "$(payload_hash)"
}

canonical_request_hash() {
  local output=$(canonical_request | shasum -a 256)
  echo "${output%% *}"
}

string_to_sign() {
  echo "AWS4-HMAC-SHA256"
  echo "${iso_timestamp}"
  echo "${date_scope}/${region}/s3/aws4_request"
  printf "$(canonical_request_hash)"
}

signature_key() {
  local secret=$(printf "AWS4${SECRET_KEY?}" | hex_key)
  local date_key=$(printf ${date_scope} | hmac_sha256 "${secret}" | hex_key)
  local region_key=$(printf ${region} | hmac_sha256 "${date_key}" | hex_key)
  local service_key=$(printf "s3" | hmac_sha256 "${region_key}" | hex_key)
  printf "aws4_request" | hmac_sha256 "${service_key}" | hex_key
}

hex_key() {
  xxd -p -c 256
}

hmac_sha256() {
  local hexkey=$1
  openssl dgst -binary -sha256 -mac HMAC -macopt hexkey:${hexkey}
}

signature() {
  string_to_sign | hmac_sha256 $(signature_key) | hex_key | sed "s/^.* //"
}

curl \
  -T "${FILE}" \
  -H "Authorization: AWS4-HMAC-SHA256 Credential=${ACCESS_KEY?}/${date_scope}/${region}/s3/aws4_request,SignedHeaders=${signed_headers},Signature=$(signature)" \
  -H "Date: ${date_header}" \
  -H "Content-Type: text/html" \
  -H "x-amz-acl: public-read" \
  -H "x-amz-content-sha256: $(payload_hash)" \
  -H "x-amz-date: ${iso_timestamp}" \
  "https://${BUCKET}.s3.amazonaws.com${DIRECTORY}/${file_basename}"
