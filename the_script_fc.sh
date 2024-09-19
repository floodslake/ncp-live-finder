#!/bin/bash


set -e
set -o pipefail
set -u


curl --version >/dev/stderr
jq --version >/dev/stderr
sort --version >/dev/stderr


offset_second="$1"
channel_list_json="$2"

file "${channel_list_json}" >/dev/stderr

now_second=$(date '+%s');
one_hours=3600
limit_second=$((${now_second} + ${offset_second}));
last_hours=$((${now_second} - ${one_hours}));

# collect live

declare -A live_timestamp_code_row_map


decode_base64() {
  local input="$1"
  echo "$input" | base64 -d
}


parse_domain() {
  local url="$1"
  local stripped_url="${url#*://}"
  local domain="${stripped_url%%/*}"
  echo "$domain"
}


live_page_info_live() {
  local url="$1"
  local domain="$2"
  local api_domain=$(parse_domain "$url")
  
  local live_page_info="$(
    curl -sS \
      -H 'fc_use_device: null' \
      "$url" | \
    jq '.data' \
  )";

  if [[ "${live_page_info}" != 'null' ]]; then
    local live_list="$(jq '.video_pages.list' <<<"${live_page_info}")";

    if [[ "${live_list}" != '[]' ]]; then
      local content_code="$(jq --raw-output '.[0].content_code' <<<"${live_list}")";

      echo "processing [${domain}/live/${content_code}]" >/dev/stderr

      local live_info="$(
        curl -sS \
          -H 'fc_use_device: null' \
          "https://{$api_domain}/fc/video_pages/${content_code}" | \
        jq '.data.video_page' \
      )";

      local live_scheduled_start_at="$(jq --raw-output '.live_scheduled_start_at' <<<"${live_info}")";
      local live_started_at="$(jq --raw-output '.live_started_at' <<<"${live_info}")";

      local video_allow_dvr_flg="$(jq --raw-output '.video.allow_dvr_flg' <<<"${live_info}")";
      [[ "${video_allow_dvr_flg}" == 'true' ]] && video_allow_dvr_flg='';

      local video_convert_to_vod_flg="$(jq --raw-output '.video.convert_to_vod_flg' <<<"${live_info}")";
      [[ "${video_convert_to_vod_flg}" == 'true' ]] && video_convert_to_vod_flg='';

      local live_scheduled_start_at_second=$(date --date="${live_scheduled_start_at}" '+%s');
      local live_started_at_second=$(date --date="${live_started_at}" '+%s');

      local title="$(jq --raw-output '.title' <<<"${live_info}")";

      local thumbnail_url="$(jq --raw-output '.thumbnail_url' <<<"${live_info}")";
      if [[ "${thumbnail_url}" != 'null' ]]; then
        thumbnail_element="<img alt=\"${title}\" src=\"${thumbnail_url}\" height=\"72\" style=\"display: block;\">"
      else
        thumbnail_element='<i>no thumbnail</i>'
      fi;
      
      if [[ "${video_allow_dvr_flg}" == 'false' ]]; then
        status_dvr='&#10060'
      else
        status_dvr=''
      fi;
      
      if [[ "${video_convert_to_vod_flg}" == 'false' ]]; then
        status_vod='&#10060'
      else
#         status_vod="&#9989"
        status_vod=''
      fi;

      local key="${live_started_at_second} ${content_code}"
      local value="$(
        cat <<-TABLE_ROW
			<tr>
				<td><a href="${domain}/lives" rel="noreferrer noopener" target="_blank">${thumbnail_element}</a></td>
				<td>${live_started_at} <a href="${domain}/live/${content_code}" rel="noreferrer noopener" target="_blank">${content_code}</a> &#x1F534<br>${title}</td>
				<td>${status_dvr}</td>
				<td>${status_vod}</td>
			</tr>
			TABLE_ROW
      )"
      live_timestamp_code_row_map["${key}"]="${value}"

      echo -e '\t''collected live' >/dev/stderr
    fi;
  fi;
}


live_page_info() {
  local url="$1"
  local domain="$2"
  local api_domain=$(parse_domain "$url")
  
  live_page_info="$(
    curl -sS \
      -H 'fc_use_device: null' \
      "$url" | \
    jq '.data' \
  )";

  if [[ "${live_page_info}" != 'null' ]]; then
    local live_list="$(jq '.video_pages.list' <<<"${live_page_info}")";

    if [[ "${live_list}" != '[]' ]]; then
      local content_code="$(jq --raw-output '.[0].content_code' <<<"${live_list}")";

      echo "processing [${domain}/live/${content_code}]" >/dev/stderr

      local live_info="$(
        curl -sS \
          -H 'fc_use_device: null' \
          "https://{$api_domain}/fc/video_pages/${content_code}" | \
        jq '.data.video_page' \
      )";

      local live_scheduled_start_at="$(jq --raw-output '.live_scheduled_start_at' <<<"${live_info}")";
      local live_started_at="$(jq --raw-output '.live_started_at' <<<"${live_info}")";

      local video_allow_dvr_flg="$(jq --raw-output '.video.allow_dvr_flg' <<<"${live_info}")";
      [[ "${video_allow_dvr_flg}" == 'true' ]] && video_allow_dvr_flg='';
      

      local video_convert_to_vod_flg="$(jq --raw-output '.video.convert_to_vod_flg' <<<"${live_info}")";
      [[ "${video_convert_to_vod_flg}" == 'true' ]] && video_convert_to_vod_flg='';
      
      local live_scheduled_start_at_second=$(date --date="${live_scheduled_start_at}" '+%s');

      local title="$(jq --raw-output '.title' <<<"${live_info}")";

      local thumbnail_url="$(jq --raw-output '.thumbnail_url' <<<"${live_info}")";
      if [[ "${thumbnail_url}" != 'null' ]]; then
        thumbnail_element="<img alt=\"${title}\" src=\"${thumbnail_url}\" height=\"72\" style=\"display: block;\">"
      else
        thumbnail_element='<i>no thumbnail</i>'
      fi;
      
      if [[ "${video_allow_dvr_flg}" == 'false' ]]; then
        status_dvr='&#10060'
      else
        status_dvr=''
      fi;
      
      if [[ "${video_convert_to_vod_flg}" == 'false' ]]; then
        status_vod='&#10060'
      else
        status_vod=''
      fi;

      if [[ ${now_second} -le ${live_scheduled_start_at_second} ]]; then
        if [[ ${live_scheduled_start_at_second} -le ${limit_second} ]]; then
          local key="${live_scheduled_start_at_second} ${content_code}"
          local value="$(
            cat <<-TABLE_ROW
						  <tr>
						    <td><a href="${domain}/lives" rel="noreferrer noopener" target="_blank">${thumbnail_element}</a></td>
						    <td>${live_scheduled_start_at} <a href="${domain}/live/${content_code}" rel="noreferrer noopener" target="_blank">${content_code}</a><br>${title}</td>
						    <td>${status_dvr}</td>
						    <td>${status_vod}</td>
						  </tr>
						TABLE_ROW
          )"
          live_timestamp_code_row_map["${key}"]="${value}"

          echo -e '\t''collected' >/dev/stderr
	  
        fi;
      fi;

      echo -e '\t''ignored' >/dev/stderr
    fi;
  fi;
}

declare -A fanclubs

fanclubs["58"]="dG9raW5vc29yYS1mYy5jb20=" #tknsr
fanclubs["100"]="cm5xcS5qcA==" #mct
fanclubs["128"]="Y2FuYW44MTgxLmNvbQ==" #cnn
fanclubs["243"]="a2Vtb21pbWlyZWZsZS5uZXQ=" #kmm
fanclubs["337"]="cml6dW5hLW9mZmljaWFsLmNvbQ==" #rzn
fanclubs["350"]="bWFsaWNlLWtpYmFuYS5jb20===" #mlc
fanclubs["434"]="dWlzZS1vZmZpY2lhbC5jb20=" #ui
fanclubs["524"]="dGVuc2hpLW5hbm8uY29t" #nn
fanclubs["561"]="c2hlZXRhLWQwNC5jb20=" #spk

for key in "${!fanclubs[@]}"; do
  decoded_string=$(decode_base64 "${fanclubs[$key]}")
  live_page_info_live "https://api.${decoded_string}/fc/fanclub_sites/$key/live_pages?page=1&live_type=1&per_page=1" "https://${decoded_string}"
  live_page_info "https://api.${decoded_string}/fc/fanclub_sites/$key/live_pages?page=1&live_type=2&per_page=1" "https://${decoded_string}"
done

echo "count of incoming live = ${#live_timestamp_code_row_map[@]}" >/dev/stderr

# sort live

declare -a live_timestamp_code_array

while read live_timestamp_code; do
  live_timestamp_code_array+=("${live_timestamp_code}")
done < <(
  for live_timestamp_code in "${!live_timestamp_code_row_map[@]}"; do
    echo "${live_timestamp_code}"
  done | \
  sort -k 1
)

# draw table

echo '<table>'

cat <<'TABLE_HEADER'
  <thead>
    <th>Thumbnail</th>
    <th>START (UTC), URL & Title</th>
    <th>DVR</th>
    <th>VOD</th>
  </thead>
TABLE_HEADER

for key in "${live_timestamp_code_array[@]}"; do
  echo "${live_timestamp_code_row_map["${key}"]}"
done

echo '</table>'
