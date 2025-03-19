#!/bin/bash
if [ -f ".env" ]; then
    source .env
fi

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

# datalad install https://datasets.datalad.org/adhd200/RawDataBIDS/Brown

# cd Brown
# datalad get sub-0026001/*

# cd $SCRATCH_DIR

# cp $BASE_DIR/freesurfer.sif .

# datalad create -D "freesurfer BIDS App" fs_bidsapp-container

# cd fs_bidsapp-container

# datalad containers-add \
#     --url ${PWD}/../freesurfer.sif \
#     freesurfer-8-0-0

# cd ../
# rm -rf freesurfer.sif

# Create the FreeSurfer BIDS App config YAML file
echo "Creating FreeSurfer BIDS App config YAML file..."
CONFIG_PATH="$SCRATCH_DIR/config_fs.yaml"

cat > "$CONFIG_PATH" << 'EOL'
# This is a config yaml file for FreeSurfer BIDS App

# Arguments passed to the application inside the container
singularity_run:
    --fs-license-file: "/orcd/scratch/bcs/001/yibei/prettymouth_babs/license.txt"
    --skip-bids-validation: ""
    --n_cpus: "16"
    $SUBJECT_SELECTION_FLAG: "--participant_label"

# Output foldername(s) to be zipped:
zip_foldernames:
    $TO_CREATE_FOLDER: "true"
    freesurfer: "8.0.0"

# How much cluster resources it needs:
cluster_resources:
    interpreting_shell: "/bin/bash"
    hard_memory_limit: 30G
    hard_runtime_limit: "12:00:00"

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

babs-init \
    --where_project ${PWD} \
    --project_name  fs_bidsapp \
    --input BIDS ${PWD}/Brown \
    --container_ds ${PWD}/fs_bidsapp-container \
    --container_name freesurfer-8-0-0 \
    --container_config_yaml_file ${PWD}/config_fs.yaml \
    --type_session single-ses \
    --type_system slurm


