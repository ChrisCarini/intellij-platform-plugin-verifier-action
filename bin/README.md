# Helper Scripts

## Installation & Execution

1) Create a GitHub PAT (Personal access token) - https://github.com/settings/tokens
2) Run the below to install + execute
    ```shell
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    GH_TOKEN="YOUR_GITHUB_PAT" python usage_finder.py 
    ```
3) Observe results.


### Sample Results
```shell
$ > GH_TOKEN="MY_GITHUB_PAT" python usage_finder.py 
Processing URL: https://api.github.com/search/code?per_page=100&q=%22verifier-version%22+%22ChrisCarini%22+%22intellij-platform-plugin-verifier-action%22+language%3AYAML
Used: 2 - Remaining 28 of 30 - Reset: 2021-11-10 09:09:41
No next URL found; ending.
1 items found.
Processing: https://github.com/ChrisCarini/sample-intellij-plugin/blob/6677f56db61bc97eef555d6847ce46b069aafaf3/.github/test_workflows/compatibility.yml

$ >
```