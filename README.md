# Azure DevOps Instance Assessment

This repository contains a set of scripts and tools to assess an Azure DevOps instance. It uses both custom PowerShell and Python scripts, as well as the GitHub Actions Importer CLI extension.

## Prerequisites

- **Docker:** Must be installed and running.
- **Python 3:** Required for running the Python assessment scripts.
- **PowerShell:** Required for running the PowerShell assessment scripts.
- **GitHub CLI (`gh`):**
  1. Download and install from [https://cli.github.com/](https://cli.github.com/).
  2. Install the GitHub Actions Importer extension:
     ```bash
     gh extension install github/gh-actions-importer
     ```

### Personal Access Tokens (PATs)

1. **GitHub Personal Access Token (classic):**
   - Scope: `workflow`.

2. **Azure DevOps Personal Access Token:**
   - Scopes:
     - `Agents Pool: Read`
     - `Build: Read`
     - `Code: Read`
     - `Release: Read`
     - `Service Connections: Read`
     - `Task Groups: Read`
     - `Variable Groups: Read`

---

## 1. GitHub Actions Importer Assessment

Follow these steps to run the GitHub Actions Importer audit:

### Configuration

Run the configuration command:
```bash
gh actions-importer configure
```
When prompted, provide the following values:
- **Select provider:** `Azure DevOps`
- **GitHub PAT:** Enter your GitHub PAT.
- **Base url of the GitHub instance:** Accept the default value.
- **Azure DevOps PAT:** Enter your Azure DevOps PAT.
- **Base url of the Azure DevOps instance:** Enter the base URL (e.g., `https://dev.azure.com/your-org`).
- **Azure DevOps organization:** Enter the name of your organization.
- **Azure DevOps project name:** Leave this **blank** to assess the entire organization.

### Update and Audit

Update the Actions Importer Docker image and run the audit:
```bash
gh actions-importer update
gh actions-importer audit azure-devops --output-dir output
```

---

## 2. Custom Assessment Scripts

These scripts provide additional insights into your Azure DevOps instance.

### Python Scripts

Install requirements:
```bash
pip install -r python-script/requirements.txt
```

Run the pipeline activity report:
```bash
python3 python-script/pipeline_activity_report_v2.py -o "https://dev.azure.com/your-org" -p "YOUR_AZURE_DEVOPS_PAT"
```

### PowerShell Scripts

Run the main assessment script:
```powershell
./pwsh-script-v2/main.ps1 -PAT "YOUR_AZURE_DEVOPS_PAT" -ORGANIZATION_URL "https://dev.azure.com/your-org" -ORGANIZATION_Name "your-org" -CSVFILENAME "inventory.csv" -ONPREM $false
```

---

## 3. Consolidate Results

After running all the scripts, move all generated CSV files into the `output` directory for final analysis:

```bash
mv pwsh-script-v2/*.csv python-script/*.csv output/
```

All assessment results will now be located in the `output/` folder.

---

## 4. Share Results

Once all reports are consolidated, please upload the entire **`output/`** folder to our secure file-sharing platform, **Eficloud**.

The access link and the password for the share will have been provided to you beforehand (with the password sent securely via **Eficrypto**). Please ensure the full folder is uploaded to include both the custom script reports and the `gh actions-importer` audit results.
