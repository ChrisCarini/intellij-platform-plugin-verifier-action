import os
from datetime import datetime
from time import sleep
import math
import requests
import base64
import yaml
import urllib.parse

TOKEN = os.environ.get('GH_TOKEN', None)
if not TOKEN:
    print("ERROR:\n\tSet the GH_TOKEN environment variable before running. Exiting.")
    print("\n\tYou can create a PAT (personal access token) on: https://github.com/settings/tokens")
    print()
    print("Exiting.")
    exit(1)

query = '"verifier-version" "ChrisCarini" "intellij-platform-plugin-verifier-action" language:YAML'
url = f'https://api.github.com/search/code?per_page=100&q={urllib.parse.quote_plus(query)}'

headers = {
    'Authorization': ('Token %s' % TOKEN)
}


# # By the time I `pip install`'d this library, I had a lot of the below code written; it took a while. :(
# from github import Github
# g = Github(TOKEN)
#
# g.search_code()

def process_response(resp):
    next_url = response.links.get('next', {}).get('url', {})
    rate_limit_limit = int(resp.headers.get('X-RateLimit-Limit'))
    rate_limit_remaining = int(resp.headers.get('X-RateLimit-Remaining'))
    rate_limit_reset = int(resp.headers.get('X-RateLimit-Reset'))
    rate_limit_used = int(resp.headers.get('X-RateLimit-Used'))
    reset_time = datetime.fromtimestamp(rate_limit_reset)
    print(f"Used: {rate_limit_used} - Remaining {rate_limit_remaining} of {rate_limit_limit} - Reset: {reset_time}")
    # If 'Retry-After' header is set, obey that; otherwise just compute it based on the rate-limit-reset.
    retry_after = resp.headers.get('Retry-After')
    if retry_after and int(retry_after) > 0:
        print(f'Sleeping for {retry_after}...')
        sleep(int(retry_after))
    elif next_url:  # Only sleep if we have a next URL to go to..
        sleep_sec = math.ceil(abs(rate_limit_reset - datetime.now().timestamp()))
        print(f"Sleeping for {sleep_sec} seconds...")
        sleep(sleep_sec)
    return next_url


items = []

while True:
    print(f'Processing URL: {url}')
    response = requests.get(url=url, headers=headers)
    # add items
    items.extend(response.json().get('items', []))
    # print rate-limit info and sleep
    next_link_url = process_response(resp=response)
    if next_link_url == {}:
        print("No next URL found; ending.")
        # print(response.links)
        # print(response.headers)
        break
    else:
        url = next_link_url

print(f'{len(items)} items found.')

results = []
for item in items:
    git_url = item.get('git_url')
    html_url = item.get('html_url')
    print(f'Processing: {html_url}', end='')
    resp = requests.get(url=git_url, headers=headers)
    content = resp.json().get('content')
    file_content = base64.b64decode(content)
    y = yaml.load(file_content, yaml.Loader)
    if isinstance(y, list):
        print()  # Print a newline - 'processing..' does not print newline.
        continue
    for jobName in y.get('jobs', {}):
        for step in y['jobs'][jobName]['steps']:
            if 'ChrisCarini/intellij-platform-plugin-verifier-action' in step.get('uses', ""):
                if 'verifier-version' in step.get('with', {}):
                    print(f'FOUND ONE -> {html_url}')
                    results.append(html_url)
    print()  # Print a newline - 'processing..' does not print newline.
