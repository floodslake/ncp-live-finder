import sys
import json
import urllib.request
import urllib.error
from datetime import datetime, timezone

def api_get(url, fanclub_site_id):
    req = urllib.request.Request(
        url,
        headers={
            "fc_site_id": str(fanclub_site_id),
            "fc_use_device": "null",
            "User-Agent": "Python-Workflow"
        }
    )
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"HTTP Error {e.code} for URL: {url}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"Error fetching {url}: {e}", file=sys.stderr)
        return None

def main():
    if len(sys.argv) < 3:
        print("Usage: python process_lives.py <offset_seconds> <channel_list_json>", file=sys.stderr)
        sys.exit(1)

    offset_second = int(sys.argv[1])
    channel_list_path = sys.argv[2]

    now_second = int(datetime.now(timezone.utc).timestamp())
    limit_second = now_second + offset_second

    try:
        with open(channel_list_path, 'r', encoding='utf-8') as f:
            channel_data = json.load(f)
    except Exception as e:
        print(f"Failed to read channel list JSON: {e}", file=sys.stderr)
        sys.exit(1)

    content_providers = channel_data.get("data", {}).get("content_providers", [])
    live_map = {} # key: (timestamp, content_code), value: html_row

    def process_channel(provider, live_type, apply_time_filter=False):
        fanclub_site_id = provider.get("id")
        domain = provider.get("domain")
        if not fanclub_site_id or not domain:
            return

        # 1. Fetch live pages
        list_url = f"https://api.nicochannel.jp/fc/fanclub_sites/{fanclub_site_id}/live_pages?page=1&live_type={live_type}&per_page=1"
        page_info = api_get(list_url, fanclub_site_id)
        if not page_info or page_info.get("data") is None:
            return

        live_list = page_info["data"].get("video_pages", {}).get("list", [])
        if not live_list:
            return

        content_code = live_list[0].get("content_code")
        if not content_code:
            return

        print(f"Processing [{domain}/live/{content_code}]", file=sys.stderr)

        # 2. Fetch video details
        detail_url = f"https://api.nicochannel.jp/fc/video_pages/{content_code}"
        detail_info = api_get(detail_url, fanclub_site_id)
        if not detail_info or not detail_info.get("data"):
            return

        live_info = detail_info["data"].get("video_page", {})
        live_scheduled_start_at = live_info.get("live_scheduled_start_at")
        if not live_scheduled_start_at:
            return

        # Parse timestamp safely
        try:
            # Handle standard ISO formats
            dt = datetime.fromisoformat(live_scheduled_start_at.replace("Z", "+00:00"))
            start_second = int(dt.timestamp())
        except Exception:
            # Fallback format handling if needed
            dt = datetime.strptime(live_scheduled_start_at[:19], "%Y-%m-%dT%H:%M:%S")
            start_second = int(dt.replace(tzinfo=timezone.utc).timestamp())

        # Apply time filters for live_type=2
        if apply_time_filter:
            if not (now_second <= start_second <= limit_second):
                print("\tignored", file=sys.stderr)
                return

        # Flags & metadata
        video_info = live_info.get("video", {})
        allow_dvr = video_info.get("allow_dvr_flg", True)
        convert_vod = video_info.get("convert_to_vod_flg", True)

        status_dvr = "&#10060;" if allow_dvr is False else ""
        status_vod = "&#10060;" if convert_vod is False else ""

        title = live_info.get("title", "")
        thumbnail_url = live_info.get("thumbnail_url")

        if thumbnail_url and thumbnail_url != "null":
            thumbnail_element = f'<img alt="{title}" src="{thumbnail_url}" width="128">'
            thumb_link_content = thumbnail_element
        else:
            thumb_link_content = "<i>no thumbnail</i>"

        red_dot = "&#x1F534;" if live_type == 1 else ""

        # HTML Table Row generation
        row_html = f"""            <tr>
                <td><a href="{domain}/lives" rel="noreferrer noopener" target="_blank">{thumb_link_content}</a></td>
                <td>{live_scheduled_start_at} <a href="{domain}/live/{content_code}" rel="noreferrer noopener" target="_blank">{content_code}</a> {red_dot}<br>{title}</td>
                <td>{status_dvr}</td>
                <td>{status_vod}</td>
            </tr>"""

        live_map[(start_second, content_code)] = row_html
        print("\tcollected", file=sys.stderr)

    # Process live_type = 1
    for provider in content_providers:
        process_channel(provider, live_type=1, apply_time_filter=False)

    # Process live_type = 2 (with time restrictions)
    for provider in content_providers:
        process_channel(provider, live_type=2, apply_time_filter=True)

    print(f"Count of incoming live = {len(live_map)}", file=sys.stderr)

    # Output final Markdown / HTML Table sorted by timestamp
    print("<table>")
    print("""  <thead>
    <th>Thumbnail</th>
    <th>START (UTC), URL & Title</th>
    <th>DVR</th>
    <th>VOD</th>
  </thead>""")
    
    for key in sorted(live_map.keys(), key=lambda x: x[0]):
        print(live_map[key])
    
    print("</table>")

if __name__ == "__main__":
    main()
