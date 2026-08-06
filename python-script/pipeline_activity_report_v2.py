import requests
from requests.auth import HTTPBasicAuth
from datetime import datetime, timedelta, timezone
import csv
from typing import List, Dict, Optional, Tuple
import argparse
import logging
import os

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Generate pipeline and repository activity reports from Azure DevOps."
    )
    parser.add_argument(
        "-o", "--organization-url", help="Azure DevOps organization URL."
    )
    parser.add_argument(
        "-p", "--personal-access-token", help="PAT used for authentication."
    )
    parser.add_argument(
        "-c",
        "--csv-file",
        help="Path to a CSV file with organization and personal_access_token columns (plus an optional custom_url column), used to run the report for multiple organizations.",
    )
    parser.add_argument(
        "-d",
        "--output-dir",
        default="output",
        help="Directory to write the generated CSV reports into (default: 'output').",
    )
    args = parser.parse_args()

    csv_file = args.csv_file or os.environ.get("ORGS_CSV")
    
    if csv_file:
        if args.organization_url or args.personal_access_token:
            parser.error(
                "--csv-file cannot be combined with --organization-url/--personal-access-token."
            )
        args.csv_file = csv_file
    elif not (args.organization_url and args.personal_access_token):
        parser.error(
            "Either --csv-file (or $ORGS_CSV env var), or both --organization-url and --personal-access-token, must be provided."
        )

    return args


def load_orgs_from_csv(csv_path: str) -> List[Dict[str, str]]:
    """Read a CSV file of organizations/PATs. Recognizes common header name variants.

    Supported columns (case-insensitive):
      - organization / org / org_name / organization_name: short org name. The
        full URL is built as https://dev.azure.com/{name} unless overridden.
      - organization_url / organisation_url / org_url / url: a full org URL,
        for backwards compatibility with single-column input.
      - custom_url: optional full URL override, for on-prem/custom domain
        deployments that don't live under dev.azure.com. Takes precedence
        over the built dev.azure.com URL, and lets rows share the same
        'organization' name while still pointing at distinct servers.
      - personal_access_token / pat / token / access_token: the PAT.
    """
    org_name_keys = {"organization", "org", "org_name", "organization_name"}
    full_url_keys = {"organization_url", "organisation_url", "org_url", "url"}
    custom_url_keys = {"custom_url", "custom_organization_url"}
    pat_keys = {"personal_access_token", "pat", "token", "access_token"}

    orgs = []
    with open(csv_path, newline="", encoding="utf-8-sig") as csvfile:
        reader = csv.DictReader(csvfile)
        if not reader.fieldnames:
            raise ValueError(f"CSV file '{csv_path}' has no header row.")

        normalized = {name: name.strip().lower() for name in reader.fieldnames}
        org_name_field = next(
            (orig for orig, norm in normalized.items() if norm in org_name_keys), None
        )
        full_url_field = next(
            (orig for orig, norm in normalized.items() if norm in full_url_keys), None
        )
        custom_url_field = next(
            (orig for orig, norm in normalized.items() if norm in custom_url_keys), None
        )
        pat_field = next(
            (orig for orig, norm in normalized.items() if norm in pat_keys), None
        )

        if not (org_name_field or full_url_field):
            raise ValueError(
                f"CSV file '{csv_path}' must contain an 'organization' (short name) "
                f"or 'organization_url' (full URL) column."
            )
        if not pat_field:
            raise ValueError(
                f"CSV file '{csv_path}' must contain a PAT column (e.g. 'personal_access_token')."
            )

        for row in reader:
            org_name = (row.get(org_name_field) or "").strip() if org_name_field else ""
            full_url = (row.get(full_url_field) or "").strip() if full_url_field else ""
            custom_url = (
                (row.get(custom_url_field) or "").strip() if custom_url_field else ""
            )
            pat = (row.get(pat_field) or "").strip()

            org_url = (
                custom_url
                or full_url
                or (f"https://dev.azure.com/{org_name}" if org_name else "")
            )
            if not org_url or not pat:
                continue
            orgs.append({"organization_url": org_url, "personal_access_token": pat})

    return orgs


class AzureDevOpsReporter:
    def __init__(self, organization_url: str, pat: str):
        self.organization_url = organization_url.strip("/")
        self.auth = HTTPBasicAuth("", pat)
        self.headers = {"Content-Type": "application/json"}
        self.on_prem = "dev.azure.com" not in self.organization_url
        self.organization_name = self.organization_url.split("/")[-1]
        self.twelve_months_ago = datetime.now(timezone.utc) - timedelta(days=365)
        self.min_time_str = self.twelve_months_ago.strftime("%Y-%m-%dT%H:%M:%S.%fZ")

    def _make_request(
        self,
        url: str,
        method: str = "GET",
        params: Dict = None,
        json_data: Dict = None,
        api_version: str = None,
        silent_404: bool = False,
    ) -> Optional[requests.Response]:
        if api_version:
            params = params or {}
            params["api-version"] = api_version

        try:
            response = requests.request(
                method,
                url,
                auth=self.auth,
                headers=self.headers,
                params=params,
                json=json_data,
            )
            if response.status_code == 404 and silent_404:
                return None
            response.raise_for_status()
            return response
        except requests.exceptions.RequestException as e:
            logging.error(f"Request failed for {url}: {e}")
            return None

    def get_all_projects(self) -> List[Dict]:
        version = "6.0" if self.on_prem else "7.0"
        url = f"{self.organization_url}/_apis/projects"
        response = self._make_request(url, api_version=version)
        return response.json().get("value", []) if response else []

    def get_all_repositories(self, project_name: str) -> Dict[str, str]:
        version = "4.1" if self.on_prem else "7.0"
        url = f"{self.organization_url}/{project_name}/_apis/git/repositories"
        response = self._make_request(url, api_version=version)
        if not response:
            return {}
        repos = response.json().get("value", [])
        return {repo["id"]: repo["name"] for repo in repos}

    def get_all_pipelines(self, project_name: str) -> List[Dict]:
        version = "6.0-preview.1" if self.on_prem else "7.0"
        url = f"{self.organization_url}/{project_name}/_apis/pipelines"
        response = self._make_request(url, api_version=version)
        return response.json().get("value", []) if response else []

    def get_pipeline_details(
        self, project_name: str, pipeline_id: int
    ) -> Optional[Dict]:
        version = "6.0-preview.1" if self.on_prem else "7.0"
        url = f"{self.organization_url}/{project_name}/_apis/pipelines/{pipeline_id}"
        response = self._make_request(url, api_version=version)
        return response.json() if response else None

    def get_pipeline_runs_count(self, project_name: str, pipeline_id: int) -> int:
        version = "6.0-preview.1" if self.on_prem else "7.0"
        url = (
            f"{self.organization_url}/{project_name}/_apis/pipelines/{pipeline_id}/runs"
        )

        all_runs = []
        continuation_token = None

        while True:
            local_headers = self.headers.copy()
            if continuation_token:
                local_headers["x-ms-continuationtoken"] = continuation_token

            try:
                response = requests.get(
                    url,
                    auth=self.auth,
                    headers=local_headers,
                    params={"api-version": version},
                )
                response.raise_for_status()
                data = response.json()
                runs = data.get("value", [])

                for run in runs:
                    if run.get("createdDate", "") >= self.min_time_str:
                        all_runs.append(run)
                    else:
                        return len(all_runs)

                continuation_token = response.headers.get("x-ms-continuationtoken")
                if not continuation_token:
                    break
            except requests.exceptions.RequestException as e:
                logging.error(f"Error fetching runs for pipeline {pipeline_id}: {e}")
                break

        return len(all_runs)

    def get_repo_info_for_pipeline(
        self, pipeline_details: Optional[Dict], repo_map: Dict[str, str]
    ) -> Tuple[str, str]:
        if not pipeline_details:
            return "Unknown", "Unknown"

        configuration = pipeline_details.get("configuration", {})
        repository = configuration.get("repository") or configuration.get(
            "designerJson", {}
        ).get("repository")

        if not repository or "type" not in repository:
            return "Unknown", "Unknown"

        repo_name = repository.get("name") or repo_map.get(
            repository.get("id", ""), "Unknown"
        )
        return repo_name, repository["type"]

    def list_release_pipelines(self, project_name: str) -> List[Dict]:
        if self.on_prem:
            url = f"{self.organization_url}/{project_name}/_apis/release/definitions"
            version = "6.0"
        else:
            url = f"https://vsrm.dev.azure.com/{self.organization_name}/{project_name}/_apis/release/definitions"
            version = "7.1"

        response = self._make_request(
            url, params={"$expand": "all"}, api_version=version
        )
        if not response:
            return []

        results = []
        min_release_time = (datetime.now(timezone.utc) - timedelta(days=365)).strftime(
            "%Y-%m-%dT%H:%M:%S.%f"
        )[:-3] + "Z"

        for pipeline in response.json().get("value", []):
            p_id = pipeline["id"]
            if self.on_prem:
                rel_url = (
                    f"{self.organization_url}/{project_name}/_apis/release/releases"
                )
            else:
                rel_url = f"https://vsrm.dev.azure.com/{self.organization_name}/{project_name}/_apis/release/releases"

            rel_params = {"definitionId": p_id, "minCreatedTime": min_release_time}
            rel_response = self._make_request(
                rel_url, params=rel_params, api_version=version
            )

            results.append(
                {
                    "pipeline_id": p_id,
                    "pipeline_name": pipeline["name"],
                    "releases": rel_response.json().get("value", [])
                    if rel_response
                    else [],
                }
            )
        return results

    def get_commit_count_last_12_months(self, project_name: str, repo_id: str) -> int:
        end_date = datetime.now(timezone.utc)
        start_date = end_date - timedelta(days=365)

        url = f"{self.organization_url}/{project_name}/_apis/git/repositories/{repo_id}/commits"
        params = {
            "searchCriteria.fromDate": start_date.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "searchCriteria.toDate": end_date.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "api-version": "6.0",
        }
        response = self._make_request(url, params=params)
        return len(response.json().get("value", [])) if response else 0

    def get_latest_commit_date(self, project_name: str, repo_id: str) -> Optional[str]:
        url = f"{self.organization_url}/{project_name}/_apis/git/repositories/{repo_id}/commits"
        response = self._make_request(url, params={"$top": 1}, api_version="6.0")
        if not response:
            return None
        commits = response.json().get("value", [])
        return commits[0]["committer"]["date"].split("T")[0] if commits else None

    def list_tfvc_activity(
        self, project_name: str
    ) -> Tuple[Optional[int], Optional[str]]:
        url = f"{self.organization_url}/{project_name}/_apis/tfvc/changesets"
        params = {
            "searchCriteria.fromDate": self.twelve_months_ago.strftime(
                "%Y-%m-%dT%H:%M:%SZ"
            ),
            "$top": 2000,
        }
        response = self._make_request(
            url, params=params, api_version="6.0", silent_404=True
        )
        if not response:
            return None, None

        data = response.json()
        count = data.get("count", 0)
        latest_date = None
        for changeset in data.get("value", []):
            created_date = changeset.get("createdDate")
            if created_date:
                if latest_date is None or created_date > latest_date:
                    latest_date = created_date

        return count, latest_date.split("T")[0] if latest_date else None

    def list_work_items_count(self, project_name: str) -> int:
        url = f"{self.organization_url}/{project_name}/_apis/wit/wiql"
        date_filter = self.twelve_months_ago.strftime("%Y-%m-%d")
        wiql = {
            "query": f"Select [System.Id] FROM WorkItems WHERE [System.ChangedDate] > '{date_filter}' AND [System.TeamProject] = '{project_name}'"
        }
        response = self._make_request(
            url, method="POST", json_data=wiql, api_version="6.0"
        )
        return len(response.json().get("workItems", [])) if response else 0

    def list_service_connections_info(self, project_name: str) -> str:
        url = f"{self.organization_url}/{project_name}/_apis/serviceendpoint/endpoints"
        response = self._make_request(url, api_version="6.0-preview")
        if not response:
            return "Error fetching connections"

        data = response.json()
        if data.get("count", 0) == 0:
            return "No service connections"

        info = [f"Quantity: {data['count']}"]
        for sc in data.get("value", []):
            info.append(f"Type: {sc['type']} Name: {sc['name']}")
        return ", ".join(info)


def generate_reports(reporter: AzureDevOpsReporter, output_dir: str = "output"):
    os.makedirs(output_dir, exist_ok=True)
    projects = reporter.get_all_projects()

    # 1. Work Items & Service Connections Report
    wi_sc_file = os.path.join(
        output_dir, f"{reporter.organization_name}_active_work_items_SC_report.csv"
    )
    with open(wi_sc_file, "w", newline="", encoding="utf-8") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(
            ["Project", "Quantity active work items", "Service connections"]
        )
        for i, project in enumerate(projects):
            p_name = project["name"]
            print(
                f"\rProgress WI/SC: {int((i + 1) / len(projects) * 100)}% ({i + 1}/{len(projects)})",
                end="",
                flush=True,
            )
            writer.writerow(
                [
                    p_name,
                    reporter.list_work_items_count(p_name),
                    reporter.list_service_connections_info(p_name),
                ]
            )
    print(f"\n✓ WI/SC report generated: {wi_sc_file}")

    # 2. Repo Activity Report
    repo_file = os.path.join(
        output_dir, f"{reporter.organization_name}_repo_activity_report.csv"
    )
    with open(repo_file, "w", newline="", encoding="utf-8") as csvfile:
        writer = csv.DictWriter(
            csvfile,
            fieldnames=[
                "Project",
                "Repo Name",
                "Size (Mb)",
                "Commits last 12 months",
                "Type",
                "Latest Commit",
            ],
        )
        writer.writeheader()
        for i, project in enumerate(projects):
            p_name = project["name"]
            print(
                f"\rProgress Repos: {int((i + 1) / len(projects) * 100)}% ({i + 1}/{len(projects)})",
                end="",
                flush=True,
            )

            version = "4.1" if reporter.on_prem else "6.0"
            url = f"{reporter.organization_url}/{p_name}/_apis/git/repositories"
            resp = reporter._make_request(url, api_version=version)
            if resp:
                for repo in resp.json().get("value", []):
                    size_mb = (
                        round(repo["size"] / (1024 * 1024), 1)
                        if repo.get("size")
                        else ""
                    )
                    writer.writerow(
                        {
                            "Project": p_name,
                            "Repo Name": repo["name"],
                            "Size (Mb)": size_mb,
                            "Commits last 12 months": reporter.get_commit_count_last_12_months(
                                p_name, repo["id"]
                            ),
                            "Type": "Azure Repos",
                            "Latest Commit": reporter.get_latest_commit_date(
                                p_name, repo["id"]
                            ),
                        }
                    )

            tfvc_count, tfvc_latest = reporter.list_tfvc_activity(p_name)
            if tfvc_count is not None:
                writer.writerow(
                    {
                        "Project": p_name,
                        "Repo Name": f"$/{p_name}",
                        "Size (Mb)": "N/A",
                        "Commits last 12 months": tfvc_count,
                        "Type": "TFVC",
                        "Latest Commit": tfvc_latest,
                    }
                )
    print(f"\n✓ Repo report generated: {repo_file}")

    # 3. Pipeline Activity Report
    pipe_file = os.path.join(
        output_dir, f"{reporter.organization_name}_pipeline_activity_report.csv"
    )
    with open(pipe_file, "w", newline="", encoding="utf-8") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(
            ["Project", "Repo Name", "Pipeline", "Type", "Runs last 12 months"]
        )
        for i, project in enumerate(projects):
            p_name = project["name"]
            print(
                f"\rProgress Pipelines: {int((i + 1) / len(projects) * 100)}% ({i + 1}/{len(projects)})",
                end="",
                flush=True,
            )

            repo_map = reporter.get_all_repositories(p_name)
            for pipe in reporter.get_all_pipelines(p_name):
                details = reporter.get_pipeline_details(p_name, pipe["id"])
                repo_name, p_type = reporter.get_repo_info_for_pipeline(
                    details, repo_map
                )
                runs = reporter.get_pipeline_runs_count(p_name, pipe["id"])
                writer.writerow([p_name, repo_name, pipe["name"], p_type, runs])

            for rel_pipe in reporter.list_release_pipelines(p_name):
                writer.writerow(
                    [
                        p_name,
                        "N/A",
                        rel_pipe["pipeline_name"],
                        "Release",
                        len(rel_pipe["releases"]),
                    ]
                )
    print(f"\n✓ Pipeline report generated: {pipe_file}")


def main():
    args = parse_args()

    if args.csv_file:
        try:
            orgs = load_orgs_from_csv(args.csv_file)
        except (OSError, ValueError) as e:
            logging.error(f"Failed to load CSV file: {e}")
            return

        if not orgs:
            logging.error(f"No valid organization/PAT rows found in '{args.csv_file}'.")
            return

        for i, org in enumerate(orgs, 1):
            logging.info(
                f"Processing organization {i}/{len(orgs)}: {org['organization_url']}"
            )
            try:
                reporter = AzureDevOpsReporter(
                    org["organization_url"], org["personal_access_token"]
                )
                generate_reports(reporter, args.output_dir)
            except Exception as e:
                logging.error(
                    f"Failed to generate reports for {org['organization_url']}: {e}"
                )
    else:
        reporter = AzureDevOpsReporter(
            args.organization_url, args.personal_access_token
        )
        generate_reports(reporter, args.output_dir)


if __name__ == "__main__":
    main()
