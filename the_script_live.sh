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
limit_second=$((${now_second} + ${offset_second}));

parse_domain() {
  local url="$1"
  local stripped_url="${url#*://}"
  local domain="${stripped_url%%/*}"
  echo "$domain"
}

live_page_info() {
  local url="$1"
  local domain="$2"
  local url_domain=$(parse_domain "$url")
  
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
          "https://api.{$url_domain}/fc/video_pages/${content_code}" | \
        jq '.data.video_page' \
      )";

      local live_scheduled_start_at="$(jq --raw-output '.live_scheduled_start_at' <<<"${live_info}")";

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
        status_dvr=""
      fi;
      
      if [[ "${video_convert_to_vod_flg}" == 'false' ]]; then
        status_vod='&#10060'
      else
        status_vod=""
      fi;

      local key="${live_scheduled_start_at_second} ${content_code}"
      local value="$(
        cat <<-TABLE_ROW
			<tr>
				<td><a href="${domain}/lives" rel="noreferrer noopener" target="_blank">${thumbnail_element}</a></td>
				<td>${live_scheduled_start_at} <a href="${domain}/live/${content_code}" rel="noreferrer noopener" target="_blank">${content_code}</a> &#x1F534<br>${title}</td>
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


# collect live

declare -A live_timestamp_code_row_map

# while read -r channel_info; do
#   fanclub_site_id="$(jq --raw-output '.id' <<<"${channel_info}")";
#   domain="$(jq --raw-output '.domain' <<<"${channel_info}")";
  
#   live_page_info "https://api.nicochannel.jp/fc/fanclub_sites/${fanclub_site_id}/live_pages?page=1&live_type=1&per_page=1" "${fc_domain}"
# done < <(<"${channel_list_json}" jq --compact-output '.data.content_providers | .[]')

live_page_info "https://api.tenshi-nano.com/fc/fanclub_sites/524/live_pages?page=1&live_type=2&per_page=1" "https://tenshi-nano.com"

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
