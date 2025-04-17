#!/bin/bash
if [ -f ".env" ]; then
    source .env
fi

# Set up logging - redirect all further output to a log file while still showing in console
LOG_FILE="$SCRATCH_DIR_ANTS/babs_script_$(date +%Y%m%d_%H%M%S).log"
echo "=== Script started at $(date) ===" | tee $LOG_FILE
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Environment: SCRATCH_DIR=$SCRATCH_DIR_ANTS, BASE_DIR=$BASE_DIR"

# Accept dataset name and input path as arguments
SITE_NAME="$1"  # Accept input path as first argument
DATASET_NAME="$2"  # Accept dataset name as second argument
SCRATCH_DIR=$SCRATCH_DIR_ANTS

if [ -z "$SITE_NAME" ] || [ -z "$DATASET_NAME" ]; then
    echo "Error: Missing arguments. Usage: $0 <site_name> <dataset_name>"
    exit 1
fi

# Extract site name from input path
echo "Processing site: $SITE_NAME for dataset: $DATASET_NAME"

source ~/.bashrc
micromamba activate simple2
mkdir -p $SCRATCH_DIR/$DATASET_NAME
cd $SCRATCH_DIR/$DATASET_NAME
echo "Current directory: $PWD"

# Check if container setup is already done
if [ -d "${PWD}/ants_bidsapp-container" ] && [ -f "${PWD}/ants_bidsapp-container/.datalad/config" ] && grep -q "ants-bidsapp-0-1-0" "${PWD}/ants_bidsapp-container/.datalad/config" 2>/dev/null; then
    echo "Container already set up, skipping container setup steps."
else
    echo "Setting up container..."
    if [ ! -f "${PWD}/ants_bidsapp.sif" ]; then
        cp $BASE_DIR/ants_bidsapp.sif .
    fi
    
    # Create the container dataset if it doesn't exist
    if [ ! -d "${PWD}/ants_bidsapp-container" ]; then
        datalad create -D "ants BIDS App" ants_bidsapp-container
    fi
    
    cd ants_bidsapp-container
    # Add the container if it's not already added
    if ! datalad containers-list 2>/dev/null | grep -q "ants-bidsapp-0-1-0"; then
        datalad containers-add \
            --url ${PWD}/../ants_bidsapp.sif \
            ants-bidsapp-0-1-0
    fi
    cd ../
    
    # Remove the SIF file if it exists
    if [ -f "${PWD}/ants_bidsapp.sif" ]; then
        rm -rf ants_bidsapp.sif
    fi
fi

# Create the FreeSurfer BIDS App config YAML file if it doesn't exist
CONFIG_PATH="$SCRATCH_DIR/$DATASET_NAME/config_ants.yaml"
if [ ! -f "$CONFIG_PATH" ]; then
    echo "Creating FreeSurfer BIDS App config YAML file..."
    cat > "$CONFIG_PATH" << 'EOL'
# This is a config yaml file for ants BIDS App
# Arguments passed to the application inside the container
bids_app_args:
    $SUBJECT_SELECTION_FLAG: "--participant-label"
    --num-threads: "8"
singularity_args:
    - --userns
    - --no-home
    - --writable-tmpfs
# Output foldername(s) to be zipped:
zip_foldernames:
    ants_bidsapp: "0-1-0"
# How much cluster resources it needs:
cluster_resources:
    interpreting_shell: "/bin/bash"
    customized_text: |
        #SBATCH --partition=mit_preemptable
        #SBATCH --cpus-per-task=8
        #SBATCH --mem=24G
        #SBATCH --time=04:00:00
        #SBATCH --job-name=ants_bidsapp
# Necessary commands to be run first:
script_preamble: |
    source ~/.bashrc 
    micromamba activate simple2
    module load apptainer/1.1.9
# Where to run the jobs:
job_compute_space: "/orcd/scratch/bcs/001/yibei/ants_compute"
required_files:
    $INPUT_DATASET_#1:
        - "anat/*_T1w.nii*"
# Alert messages that might be found in log files of failed jobs:
alert_log_messages:
    stdout:
        - "ERROR:"
        - "Cannot allocate memory"
        - "Numerical result out of range"
EOL
    echo "YAML config file created at $CONFIG_PATH"
else
    echo "Config file already exists at $CONFIG_PATH, skipping creation"
fi

cd $SCRATCH_DIR/$DATASET_NAME

# Initialize BABS with the dataset-specific output directory
babs init \
    --datasets BIDS=$DATALAD_SET_DIR/$DATASET_NAME/$SITE_NAME \
    --container_ds ${PWD}/ants_bidsapp-container \
    --container_name ants-bidsapp-0-1-0 \
    --container_config $SCRATCH_DIR/$DATASET_NAME/config_ants.yaml \
    --processing_level subject \
    --queue slurm \
    $SCRATCH_DIR/$DATASET_NAME/ants_bidsapp_${SITE_NAME}/

cd $SCRATCH_DIR/$DATASET_NAME/ants_bidsapp_${SITE_NAME}
babs submit ${PWD}
# babs check-setup ${PWD} --job_test

# # If babs check-setup is successful, submit all jobs
# if [ $? -eq 0 ]; then
#     echo "BABS setup check successful, submitting all jobs..."
#     babs submit $PWD --all
# else
#     echo "BABS setup check failed, not submitting jobs."
#     exit 1
# fi