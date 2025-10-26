# BABS Setup Notes for FreeSurfer BIDS App
**Date**: September 26, 2025

## Overview
Successfully set up and deployed BABS (BIDS App Bootstrap) to run FreeSurfer 8.0.0 on the ABIDE-I Caltech dataset with NIDM support.

## Environment Setup

### Created New Micromamba Environment
```bash
# Downloaded official BABS HPC environment file
wget https://raw.githubusercontent.com/PennLINC/babs/refs/heads/main/environment_hpc.yml

# Created environment from YAML
micromamba create -f environment_hpc.yml -y

# Installed BABS
micromamba activate babs
pip install babs
```

## Key Fixes Applied to `fs_babs_script0926.sh`

### 1. Updated Environment Activation
- Changed from `micromamba activate simple2` to `micromamba activate babs`

### 2. Fixed BABS Command Syntax
- Removed `--datasets` flag from `babs init` (not used in BABS 0.5.x)
- Datasets are now configured in the YAML file instead

### 3. Corrected Data Paths
- BIDS data: `$DATALAD_SET_DIR/$DATASET_NAME/$SITE_NAME/raw_data`
- NIDM data: `$DATALAD_SET_DIR/$DATASET_NAME/$SITE_NAME/derivatives/nidm`
- Used `$SITE_NAME` variable instead of hardcoding "Caltech"

### 4. Fixed YAML Syntax Issues
- Escaped special variables: `$SUBJECT_SELECTION_FLAG` → `"$SUBJECT_SELECTION_FLAG"`
- Escaped required_files key: `$INPUT_DATASET_#1` → `"$INPUT_DATASET_#1"`

### 5. Resolved Git Ownership Issues
```bash
git config --global --add safe.directory '/orcd/data/satra/002/datasets/simple2_datalad/study_abide/Caltech/raw_data/.git'
git config --global --add safe.directory '/orcd/data/satra/002/datasets/simple2_datalad/study_abide/Caltech/derivatives/nidm/.git'
```

### 6. Created Required Directories
```bash
mkdir -p /orcd/scratch/bcs/001/yibei/freesurfer_compute_0926
```

## BABS Project Details

### Project Location
`/orcd/scratch/bcs/001/yibei/simple2/fs_bidsapp_babs/study_abide_0926/fs_bidsapp_Caltech_0926`

### Container
- SIF file: `freesurfer_bidsapp0926.sif`
- Container name in BABS: `freesurfer-bidsapp-0-1-0`

### Input Data
- **BIDS Dataset**: `/orcd/data/satra/002/datasets/simple2_datalad/study_abide/Caltech/raw_data`
- **NIDM Dataset**: `/orcd/data/satra/002/datasets/simple2_datalad/study_abide/Caltech/derivatives/nidm`
- **Subjects**: 38 subjects from Caltech site (sub-0051456 through sub-0051493)

### SLURM Configuration
- Partition: `mit_preemptable`
- CPUs per task: 8
- Memory: 24GB
- Time limit: 2.5 hours per subject
- Compute space: `/orcd/scratch/bcs/001/yibei/freesurfer_compute_0926`

## Running the Script

### Basic Usage
```bash
cd /home/yibei/simple2_bidsapp_babs
./fs_babs_script0926.sh <SITE_NAME> <DATASET_NAME>

# Example for Caltech site:
./fs_babs_script0926.sh Caltech study_abide
```

### Manual BABS Commands
```bash
# Navigate to project
cd /orcd/scratch/bcs/001/yibei/simple2/fs_bidsapp_babs/study_abide_0926/fs_bidsapp_Caltech_0926

# Activate environment
micromamba activate babs

# Check setup
babs check-setup .

# Submit jobs
babs submit

# Check status
babs status

# Merge results (after completion)
babs merge
```

## Job Submission Status
- Successfully submitted 38 FreeSurfer jobs on September 26, 2025
- Each job processes one subject through FreeSurfer recon-all pipeline
- NIDM will be built incrementally since NIDM directory exists

## Important Notes
1. The script now correctly handles both BIDS and NIDM datasets
2. Git safe directories must be configured for DataLad datasets owned by different users
3. The compute directory must exist before job submission
4. FreeSurfer license is configured at `/orcd/scratch/bcs/001/yibei/prettymouth_babs/license.txt`

## Environment Variables (from .env)
- `DATALAD_SET_DIR`: `/orcd/data/satra/002/datasets/simple2_datalad`
- `SCRATCH_DIR_FS`: `/orcd/scratch/bcs/001/yibei/simple2/fs_bidsapp_babs`

## Next Steps
1. Monitor job progress with `babs status`
2. Once complete, merge results with `babs merge`
3. Clone output RIA to access results
4. Can run for other sites by changing the SITE_NAME parameter