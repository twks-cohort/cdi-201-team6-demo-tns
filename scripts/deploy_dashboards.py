import json
import os
import sys
from xmlrpc.server import CGIXMLRPCRequestHandler

import requests

base_url = "https://team##201stack.grafana.net/api/dashboards/db"
headers = {
    "Accept": "application/json",
    "Content-Type": "application/json",
    "Authorization": f'Bearer {os.getenv("STACK_MANAGEMENT_TOKEN")}'
}

def upsert_dashboard(dashboard_url, headers, dashboard_json):
    response = requests.post(dashboard_url, headers=headers, json=dashboard_json)
    response.raise_for_status()

directory = os.fsencode("observe/dashboards")

for file in os.listdir(directory):
    filename = os.fsdecode(file)
    if filename.endswith(".json"):
        upsert_dashboard(base_url, headers, json.load(open(os.path.join(os.fsdecode(directory), filename))))

print("Dashboards deployed successfully")
