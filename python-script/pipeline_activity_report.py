import requests
from requests.auth import HTTPBasicAuth
from datetime import datetime, timedelta, timezone
import csv
from typing import List, Dict, Optional
import json
import argparse


parser = argparse.ArgumentParser(description="Generate pipeline and repository activity reports from Azure DevOps.")
parser.add_argument("-o", "--organization-url",help="Override the default Azure DevOps organization URL.")
parser.add_argument("-p", "--personal-access-token", help="Override the PAT used for authentication.")

args = parser.parse_args()

ORGANIZATION_URL = args.organization_url
PERSONAL_ACCESS_TOKEN = args.personal_access_token

ORGANIZATION = ORGANIZATION_URL.split("/")[-1]
if "dev.azure.com" in ORGANIZATION_URL:ONPREM = False
else:ONPREM = True

twelve_months_ago = datetime.now(timezone.utc) - timedelta(days=365)

min_time = twelve_months_ago.strftime('%Y-%m-%dT%H:%M:%S.%fZ')

# Authentication
auth = HTTPBasicAuth('', PERSONAL_ACCESS_TOKEN)
headers = {'Content-Type': 'application/json'}
workspace = "SEB"

def print_to_json_file(dict, file_name):
    data = json.dumps(dict, indent=3, ensure_ascii=False)
    with open(f"{file_name}.json", "w", encoding='utf-8') as outfile:
        outfile.write(data)

def get_all_projects() -> List[Dict]:
    if ONPREM:
        url = f"{ORGANIZATION_URL}/_apis/projects?api-version=6.0"
    else:
        url = f"{ORGANIZATION_URL}/_apis/projects?api-version=7.0"
    response = requests.get(url, auth=auth, headers=headers)
    response.raise_for_status()
    return response.json().get('value', [])

def get_all_repositories(project_name: str) -> Dict[str, str]:
    # 4.1
    if ONPREM:
        url = f"{ORGANIZATION_URL}/{project_name}/_apis/git/repositories?api-version=4.1"
    else:
        url = f"{ORGANIZATION_URL}/{project_name}/_apis/git/repositories?api-version=7.0"
    response = requests.get(url, auth=auth, headers=headers)
    response.raise_for_status()
    repos = response.json().get('value', [])
    return {repo['id']: repo['name'] for repo in repos}

def get_all_pipelines(project_name: str) -> List[Dict]:
    if ONPREM:
        url = f"{ORGANIZATION_URL}/{project_name}/_apis/pipelines?api-version=6.0-preview.1"
    else:
        url = f"{ORGANIZATION_URL}/{project_name}/_apis/pipelines?api-version=7.0"
    response = requests.get(url, auth=auth, headers=headers)
    response.raise_for_status()
    return response.json().get('value', [])

def get_pipeline_details(project_name: str, pipeline_id: int) -> Optional[Dict]:
    if ONPREM:
        url = f"{ORGANIZATION_URL}/{project_name}/_apis/pipelines/{pipeline_id}?api-version=6.0-preview.1"# 6.0-preview.1
    else:

        url = f"{ORGANIZATION_URL}/{project_name}/_apis/pipelines/{pipeline_id}?api-version=7.0"
    try:
        response = requests.get(url, auth=auth, headers=headers)
        response.raise_for_status()
        return response.json()
    except:
        return None

def get_pipeline_runs_count(project_name: str, pipeline_id: int, min_time: str) -> int:
    if ONPREM:
        url = f"{ORGANIZATION_URL}/{project_name}/_apis/pipelines/{pipeline_id}/runs?api-version=6.0-preview.1"# version=6.0-preview.1
    else:
        url = f"{ORGANIZATION_URL}/{project_name}/_apis/pipelines/{pipeline_id}/runs?api-version=7.0"
    
    all_runs = []
    continuation_token = None
    
    while True:
        params = {}
        if continuation_token:
            headers['x-ms-continuationtoken'] = continuation_token
        
        response = requests.get(url, auth=auth, headers=headers, params=params)
        response.raise_for_status()

        #if response.json() and response.json()["count"] > 0:
            #print_to_json_file(response.json(), f"{workspace}/pipeline_{pipeline_id}_details")

            #exit()
        data = response.json()
        runs = data.get('value', [])
        
        # Filter runs by date
        for run in runs:
            created_date = run.get('createdDate', '')
            if created_date >= min_time:
                all_runs.append(run)
            else:
                # Since runs are ordered by date (newest first), we can break early
                return len(all_runs)
        
        # Check for continuation token
        continuation_token = response.headers.get('x-ms-continuationtoken')
        if not continuation_token:
            break
    
    return len(all_runs)

def get_repository_name_for_pipeline(pipeline_details: Optional[Dict], repo_map: Dict[str, str]) -> str:
    if not pipeline_details:
        return 'Unknown', 'Unknown'
    
    # Try to get repository from configuration
    configuration = pipeline_details.get('configuration', {})
    if "repository" in configuration : repository = configuration["repository"]
    elif "designerJson" in configuration and "repository" in configuration["designerJson"] : repository = configuration["designerJson"]["repository"]
    
    else:return 'Unknown', 'Unknown'
    
    if not "type" in repository:
        return 'Unknown', 'Unknown'
    
    if "name" in repository:
        repo_name = repository["name"]
    else:
        repo_name = repo_map.get(repository.get('id', ''), 'Unknown')

    return repo_name, repository["type"]


def list_release_pipelines(project):
    if ONPREM: 
        #base_url = f"http://{ORGANIZATION}/{project}/_apis" #  https://{instance}/{collection}/{project}/_apis/release/definitions?api-version=6.0
        pipelines_url = f"{ORGANIZATION_URL}/{project}/_apis/release/definitions?$expand=all&api-version=6.0"
    else:
        base_url = f"https://vsrm.dev.azure.com/{ORGANIZATION}/{project}/_apis"
        pipelines_url = f"{base_url}/release/definitions?$expand=all&api-version=7.1"

    #twelve_months_ago = (datetime.now(timezone.utc) - timedelta(days=365)).isoformat()
    
    
    twelve_months_ago = (datetime.now(timezone.utc) - timedelta(days=365)).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z'

    pipelines_response = requests.get(pipelines_url, auth=auth, headers=headers)


    if not pipelines_response.ok:
        print(f"Failed to fetch pipelines for project {project}: {pipelines_response.status_code} - {pipelines_response.text}")
        return []
    elif not pipelines_response.json() or "value" not in pipelines_response.json():
        #print(f"No pipelines found for project {project}: {pipelines_response.status_code} - {pipelines_response.text}")
        return []
    results = []
    
    for pipeline in pipelines_response.json()["value"]:
        pipeline_id = pipeline['id']
        pipeline_name = pipeline['name']
        if ONPREM:
            releases_url = f"{ORGANIZATION_URL}/{project}/_apis/release/releases?definitionId={pipeline_id}&minCreatedTime={twelve_months_ago}&api-version=6.0"
        else:
            releases_url = f"{base_url}/release/releases?definitionId={pipeline_id}&minCreatedTime={twelve_months_ago}&api-version=7.1"

        releases_response = requests.get(releases_url, auth=auth, headers=headers)
        if not releases_response.ok:
            print(f"Failed to fetch releases for pipeline {pipeline_id} in project {project}: {releases_response.status_code} - {releases_response.text}")
            return []
        
        releases = releases_response.json().get('value', [])
        results.append({
            'pipeline_id': pipeline_id,
            'pipeline_name': pipeline_name,
            'releases': releases
        })

    return results


def list_commits(AZURE_ORGANISATION_URL, PROJECT, repositoryId, start_date, end_date):
    URL = f"{AZURE_ORGANISATION_URL}/{PROJECT}/_apis/git/repositories/{repositoryId}/commits?searchCriteria.fromDate={start_date}&searchCriteria.toDate={end_date}&api-version=6.0"
    response = requests.get(URL, auth=auth, headers=headers)

    return response.json()

def get_commit_count_last_12_months(org_url, project_name, repo_id):
    try:
        # Calculate date range (last 12 months)
        end_date = datetime.now()
        start_date = end_date - timedelta(days=365)
        
        # Format dates for API (ISO 8601 format)
        start_date_str = start_date.strftime('%Y-%m-%dT%H:%M:%SZ')
        end_date_str = end_date.strftime('%Y-%m-%dT%H:%M:%SZ')
        
        # Get commits from the last 12 months
        commits_response = list_commits(org_url, project_name, repo_id, start_date_str, end_date_str)

        if 'value' in commits_response:
            return len(commits_response['value'])
        else:
            return 0
    except Exception as e:
        print(f"Error getting commits for repo {repo_id} project: {project_name}: {str(e)}")
        return 0
    
def list_repo(target_project_git):
    if ONPREM:
        URL = f"{ORGANIZATION_URL}/{target_project_git}/_apis/git/repositories?api-version=4.1"
    else:
        URL = f"{ORGANIZATION_URL}/{target_project_git}/_apis/git/repositories?api-version=6.0"

    response = requests.get(URL, auth=auth, headers=headers)
    return response.json()


def list_tfvc_repositories(project_name: str) -> List[Dict]:

    url = f"{ORGANIZATION_URL}/{project_name}/_apis/tfvc/changesets?api-version=6.0" 
    params = {
                "searchCriteria.fromDate": twelve_months_ago,
                "$top": 2000,
                "api-version": "6.0",
            }

    response = requests.get(url, auth=auth, params=params,headers=headers)
    if not response.ok:
        return None, None
    
    #print_to_json_file(response.json(), f"{workspace}/{project_name}_tfvc_changesets")
    latest_date = ""
    #exit()
    for changeset in response.json().get("value", []):
        created_date = changeset.get('createdDate')
        
        latest_date = None
        for changeset in response.json().get("value", []):
            created_date = changeset.get('createdDate')
            if created_date:
                if latest_date is None or created_date > latest_date:
                    latest_date = created_date
    if latest_date:
        latest_date = latest_date.split("T")[0]
    return response.json()["count"], latest_date



def get_latest_commit(project_name, repo_id):
    url = f"{ORGANIZATION_URL}/{project_name}/_apis/git/repositories/{repo_id}/commits?api-version=6.0&$top=1"
    response = requests.get(url, auth=auth, headers=headers)
    if not response.ok:
        return None
    
    commits = response.json().get('value', [])

    
    if not commits:
        return None
    #print_to_json_file(commits, f"{project_name}_{repo_id}_latest_commit")
    return commits[0]["committer"]["date"].split("T")[0]

def generate_repo_activity_report():

    output_file=f'repo_activity_report-{ORGANIZATION}.csv'


    projects = get_all_projects()
    
    with open(output_file, 'w', newline='', encoding='utf-8') as csvfile:
        fieldnames = ['Project', 'Repo Name', 'Size (Mb)', 'Commits last 12 months', 'Type','Latest Commit']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        
        # Process each project
        for index, project in enumerate(projects):
            percent = (index + 1) / len(projects) * 100
        
            print(f"\rFetching Azure repos | Progress projects: {int(percent)}% ({index + 1}/{len(projects)})", end='', flush=True)

            project_name = project['name']
            
            try:
                repos_response = list_repo(project_name)
                #print_to_json_file(repos_response, f"{project_name}_repos_response")
                #exit()
                if 'value' not in repos_response:
                    continue
                
                repos = repos_response['value']
                #print(f"  Found {len(repos)} repositories")
                
                # Process each repository
                for repo in repos:
                   #print_to_json_file(repo, f"repo_details_{project_name}_{repo['name']}_")
                    #if not repo["name"] == "eShopOnWeb": continue
                    
                    repo_name = repo['name']
                    repo_id = repo['id']
                    size = repo.get('size', "")
                    
                    size_mb = round(size / (1024 * 1024), 1) if size and size > 0 else ""
                    #print(f"    Analyzing repo: {repo_name}...")
                    #print_to_json_file(repo, f"{project_name}_{repo_name}_repo_details")
                    # Get commit count for last 12 months
                    commit_count = get_commit_count_last_12_months(ORGANIZATION_URL, project_name, repo_id)

                    latest_commit = get_latest_commit(project_name, repo_id)



                    writer.writerow({
                        'Project': project_name,
                        'Repo Name': repo_name,
                        'Size (Mb)': size_mb,
                        'Commits last 12 months': commit_count,
                        'Type': 'Azure Repos',
                        'Latest Commit': latest_commit
                    })
                tfvc, latest_commit = list_tfvc_repositories(project_name)
                
                if tfvc is not None:
                    writer.writerow({
                        'Project': project_name,
                        'Repo Name': f"$/{project_name}",
                        'Size (Mb)': "N/A",
                        'Commits last 12 months': tfvc,
                        'Type': 'TFVC',
                        'Latest Commit': latest_commit
                    })

                    
            except Exception as e:
                print(f"Error processing project {project_name}: {str(e)}")
                continue
    
    print(f"\n✓ Report generated successfully: {output_file}")

def get_latest_commitasd(project_name, repo_id):
    url = f"{ORGANIZATION_URL}/{project_name}/_apis/git/repositories/{repo_id}/commits?api-version=6.0&$top=1"
    response = requests.get(url, auth=auth, headers=headers)

def list_work_items_wiql(project):

    current_date = twelve_months_ago.strftime('%Y-%m-%d')

    #print(f"Fetching active work items for project {project} with WIQL query. Current date filter: {current_date}")
    
    WIQL = {
        "query": f"Select * FROM WorkItems WHERE [System.ChangedDate] > '{current_date}' AND [System.TeamProject] = '{project}'"
        #"query": f"Select * FROM WorkItems WHERE [System.Id] <> '12344'"
    }
    
    URL = f"{ORGANIZATION_URL}/{project}/_apis/wit/wiql?api-version=6.0"
    response = requests.post(URL, json=WIQL, auth=auth, headers=headers)

    #response = requests.post(URL, headers=headers, json=wiql, verify=False)
    if not response.ok:print(f"Error; No response {response.text}");exit()
    res = response.json()
    #print_to_json_file(res, f"{workspace}/{project}_wiql_response")
    return len(res["workItems"])


def list_service_connections(project):
    service_connection_data = "No service connections"
    URL = f"{ORGANIZATION_URL}/{project}/_apis/serviceendpoint/endpoints?api-version=6.0-preview"
    response = requests.get(URL, auth=auth, headers=headers)

    if not response.ok:print(f"Error; No response {response.text}");exit()
    res = response.json()
    if res["count"] > 0:
        #print_to_json_file(res, f"{workspace}/{project}_SC_response")
        service_connection_data = f"Quantity: {res['count']}"
        for sc in res["value"]:
            
            service_connection_data += f", Type: {sc['type']} Name: {sc['name']}"
        #print(f"project {project} - {service_connection_data}")
    return service_connection_data


def generate_active_work_items_SC_report():
    projects = get_all_projects()
    csv_filename = f"active_work_items_SC_report_{ORGANIZATION}.csv"
    with open(csv_filename, 'w', newline='', encoding='utf-8') as csvfile:
        csv_writer = csv.writer(csvfile)
        csv_writer.writerow(['Project', 'Quantity active work items', 'Service connections'])

        for index, project in enumerate(projects):
            try:
                percent = (index + 1) / len(projects) * 100
                print(f"\rFetching active work items and service connections | Progress projects: {int(percent)}% ({index + 1}/{len(projects)})", end='', flush=True)
                project_name = project['name']
                
                active_workitems = list_work_items_wiql(project_name)
                #print(f"project {project_name} - {active_workitems} active work items.")
                SC = list_service_connections(project_name)

                csv_writer.writerow([project_name, active_workitems, SC])
            except Exception as e:
                print(f"Error processing project {project_name}: {str(e)}")
                csv_writer.writerow([project_name, 'ERROR', 'ERROR'])
    print(f"\n✓ Report active work items and service connections generated successfully: {csv_filename}")

def main():
    generate_active_work_items_SC_report()
    #exit()
    generate_repo_activity_report()

    
    
    projects = get_all_projects()

    #print(f"Analyzing pipeline runs from {twelve_months_ago.strftime('%Y-%m-%d')} to now\n")
    
    #csv_filename = f"pipeline_activity_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    csv_filename = f"pipeline_activity_report.csv"
    
    with open(csv_filename, 'w', newline='', encoding='utf-8') as csvfile:
        csv_writer = csv.writer(csvfile)
        csv_writer.writerow(['Project', 'Repo Name', 'Pipeline', 'Type', 'Runs last 12 months'])
        
        
        
        
        for index, project in enumerate(projects):
            percent = (index + 1) / len(projects) * 100
        
            print(f"\rFetching ADO pipelines | Progress projects: {int(percent)}% ({index + 1}/{len(projects)})", end='', flush=True)

            project_name = project['name']
            
            #try:
            repo_map = get_all_repositories(project_name)
            
            pipelines = get_all_pipelines(project_name)
            
            for pipeline in pipelines:
                pipeline_id = pipeline['id']
                pipeline_name = pipeline['name']
                try:
                    pipeline_details = get_pipeline_details(project_name, pipeline_id)
                    repo_name, type = get_repository_name_for_pipeline(pipeline_details, repo_map)

                    run_count = get_pipeline_runs_count(project_name, pipeline_id, min_time)
                    
                    csv_writer.writerow([project_name, repo_name, pipeline_name, type, run_count])
                
                except Exception as e:
                    print(f"Error processing pipeline {pipeline_name} in project {project_name}: {str(e)}")
                    print_to_json_file(pipeline_details, f"pipeline_error_{pipeline_id}")
                    csv_writer.writerow([project_name, 'ERROR', pipeline_name, 'ERROR'])

            release_pipelines_data = list_release_pipelines(project_name)
            #print(release_pipelines_data)
            try:
                for release_pipeline in release_pipelines_data:
                    pipeline_name = release_pipeline['pipeline_name']
                    releases = release_pipeline['releases']
                    run_count = len(releases)
                    csv_writer.writerow([project_name, 'N/A', pipeline_name, 'Release', run_count])
            
            except Exception as e:
                print_to_json_file(release_pipeline, f"release_pipeline_error_{pipeline_id}")
                print(f"Error processing release pipelines in project {project_name}, pipeline: {pipeline_name}: {str(e)}")
                csv_writer.writerow([project_name, 'ERROR', pipeline_name, 'Release', 'ERROR'])
                        
            
    
    print(f"\nReport saved to: {csv_filename}")

if __name__ == "__main__":
    main()
