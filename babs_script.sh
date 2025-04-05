#!/bin/bash
if [ -f ".env" ]; then
    source .env
fi

# Define datalad URL and extract dataset name
DATALAD_URL="https://datasets.datalad.org/adhd200/RawDataBIDS/Brown"
DATASET_NAME=$(basename "$DATALAD_URL")

# Set up logging - redirect all further output to a log file while still showing in console
LOG_FILE="$SCRATCH_DIR/babs_script_$(date +%Y%m%d_%H%M%S).log"
echo "=== Script started at $(date) ===" | tee $LOG_FILE
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Environment: SCRATCH_DIR=$SCRATCH_DIR, BASE_DIR=$BASE_DIR"
echo "Dataset installation and container setup completed"

source ~/.bashrc

micromamba activate simple2

mkdir -p $SCRATCH_DIR

cd $SCRATCH_DIR

echo "Current directory: $PWD"
datalad install "$DATALAD_URL"

cd $SCRATCH_DIR

cp /home/yibei/fs_bidsapp_babs/freesurfer_bidsapp.sif .

datalad create -D "freesurfer BIDS App" fs_bidsapp-container

cd fs_bidsapp-container

datalad containers-add \
    --url ${PWD}/../freesurfer_bidsapp.sif \
    freesurfer-bidsapp-0-1-0

cd ../
rm -rf freesurfer_bidsapp.sif

# Create the FreeSurfer BIDS App config YAML file
echo "Creating FreeSurfer BIDS App config YAML file..."
CONFIG_PATH="$SCRATCH_DIR/config_fs.yaml"

cat > "$CONFIG_PATH" << 'EOL'
# This is a config yaml file for FreeSurfer BIDS App

# Arguments passed to the application inside the container
bids_app_args:
    $SUBJECT_SELECTION_FLAG: "--participant_label"
    --fs-license-file: "/orcd/scratch/bcs/001/yibei/prettymouth_babs/license.txt"
    --skip-bids-validation: ""

singularity_args:
    - --userns
    - --no-home
    - --writable-tmpfs

# Output foldername(s) to be zipped:
zip_foldernames:
    freesurfer_bidsapp: "0-1-0"

# How much cluster resources it needs:
cluster_resources:
    interpreting_shell: "/bin/bash"
    customized_text: |
        #SBATCH --partition=mit_normal
        #SBATCH --cpus-per-task=1
        #SBATCH --mem=24G
        #SBATCH --time=02:30:00
        #SBATCH --job-name=fs_bidsapp

# Necessary commands to be run first:
script_preamble: |
    source ~/.bashrc 
    micromamba activate simple2
    module load apptainer/1.1.9

# Where to run the jobs:
job_compute_space: "/orcd/scratch/bcs/001/yibei/freesurfer_compute"

required_files:
    $INPUT_DATASET_#1:
        - "anat/*_T1w.nii*"

# Alert messages that might be found in log files of failed jobs:
alert_log_messages:
    stdout:
        - "ERROR:"
        - "Cannot allocate memory"
        - "mris_curvature_stats: Could not open file"
        - "Numerical result out of range"
        - "FreeSurfer failed"
        - "recon-all: error"
EOL

echo "YAML config file created at $CONFIG_PATH"

# # Clean up existing directory if it exists
# rm -rf ${PWD}/fs_bidsapp

babs init \
    --datasets BIDS=${PWD}/$DATASET_NAME \
    --container_ds ${PWD}/fs_bidsapp-container \
    --container_name freesurfer-bidsapp-0-1-0 \
    --container_config ${PWD}/config_fs.yaml \
    --processing_level subject \
    --queue slurm \
    ${PWD}/fs_bidsapp/

cd ${PWD}/fs_bidsapp

babs check-setup ${PWD} --job_test

# babs status $PWD 

# babs-status \
#     --resubmit-job sub-0026001

# babs submit $PWD 