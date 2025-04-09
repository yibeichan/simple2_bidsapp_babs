#!/bin/bash
if [ -f ".env" ]; then
    source .env
fi

# Set up logging - redirect all further output to a log file while still showing in console
LOG_FILE="$SCRATCH_DIR/babs_script_$(date +%Y%m%d_%H%M%S).log"
echo "=== Script started at $(date) ===" | tee $LOG_FILE
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Environment: SCRATCH_DIR=$SCRATCH_DIR, BASE_DIR=$BASE_DIR"

# Accept dataset name and input path as arguments
INPUT_PATH="$1"  # Accept input path as first argument
DATASET_NAME="$2"  # Accept dataset name as second argument

if [ -z "$INPUT_PATH" ] || [ -z "$DATASET_NAME" ]; then
    echo "Error: Missing arguments. Usage: $0 <input_path> <dataset_name>"
    exit 1
fi

# Extract site name from input path
SITE_NAME=$(basename "$INPUT_PATH")
echo "Processing site: $SITE_NAME from path: $INPUT_PATH for dataset: $DATASET_NAME"

source ~/.bashrc
micromamba activate simple2
mkdir -p $SCRATCH_DIR/$DATASET_NAME
cd $SCRATCH_DIR/$DATASET_NAME
echo "Current directory: $PWD"

# Create site directory
mkdir -p "$SCRATCH_DIR/$DATASET_NAME/$SITE_NAME"

# Copy only anat folders from the dataset, but skip existing files
echo "Copying only anat folders from $INPUT_PATH to $SCRATCH_DIR/$DATASET_NAME/$SITE_NAME (skipping existing files)"

# Find all anat folders
find "$INPUT_PATH" -type d -name "anat" | while read anat_dir; do
  # Get the relative path of this anat folder within the original dataset
  rel_path=$(echo "$anat_dir" | sed "s|$INPUT_PATH/||")
  
  # Create the target directory
  target_dir="$SCRATCH_DIR/$DATASET_NAME/$SITE_NAME/$rel_path"
  mkdir -p "$target_dir"
  
  # Copy all files from the anat directory, but skip if they already exist
  find "$anat_dir" -type f | while read src_file; do
    # Get the filename
    filename=$(basename "$src_file")
    # Check if file already exists
    if [ -f "$target_dir/$filename" ]; then
      echo "Skipping existing file: $target_dir/$filename"
    else
      echo "Copying: $src_file -> $target_dir/$filename"
      cp "$src_file" "$target_dir/"
    fi
  done
done

# Also copy the dataset_description.json file and other important BIDS files if they exist
for bids_file in dataset_description.json README participants.tsv participants.json CHANGES; do
  target_file="$SCRATCH_DIR/$DATASET_NAME/$SITE_NAME/$bids_file"
  if [ -f "$INPUT_PATH/$bids_file" ]; then
    if [ -f "$target_file" ]; then
      echo "Skipping existing BIDS file: $bids_file"
    else
      echo "Copying BIDS file: $bids_file"
      cp "$INPUT_PATH/$bids_file" "$target_file"
    fi
  fi
done

# Initialize the copied directory as a datalad dataset
echo "Initializing the copied directory as a datalad dataset..."
cd "$SCRATCH_DIR/$DATASET_NAME/$SITE_NAME"
datalad create -f -d .
# Add all files to the dataset
datalad save -m "Initial commit of copied BIDS data"
cd "$SCRATCH_DIR/$DATASET_NAME"

# Check if container setup is already done
if [ -d "${PWD}/fs_bidsapp-container" ] && [ -f "${PWD}/fs_bidsapp-container/.datalad/config" ] && grep -q "freesurfer-bidsapp-0-1-0" "${PWD}/fs_bidsapp-container/.datalad/config" 2>/dev/null; then
    echo "Container already set up, skipping container setup steps."
else
    echo "Setting up container..."
    if [ ! -f "${PWD}/freesurfer_bidsapp.sif" ]; then
        cp /home/yibei/fs_bidsapp_babs/freesurfer_bidsapp.sif .
    fi
    
    # Create the container dataset if it doesn't exist
    if [ ! -d "${PWD}/fs_bidsapp-container" ]; then
        datalad create -D "freesurfer BIDS App" fs_bidsapp-container
    fi
    
    cd fs_bidsapp-container
    # Add the container if it's not already added
    if ! datalad containers-list 2>/dev/null | grep -q "freesurfer-bidsapp-0-1-0"; then
        datalad containers-add \
            --url ${PWD}/../freesurfer_bidsapp.sif \
            freesurfer-bidsapp-0-1-0
    fi
    cd ../
    
    # Remove the SIF file if it exists
    if [ -f "${PWD}/freesurfer_bidsapp.sif" ]; then
        rm -rf freesurfer_bidsapp.sif
    fi
fi

# Create the FreeSurfer BIDS App config YAML file if it doesn't exist
CONFIG_PATH="$SCRATCH_DIR/$DATASET_NAME/config_fs.yaml"
if [ ! -f "$CONFIG_PATH" ]; then
    echo "Creating FreeSurfer BIDS App config YAML file..."
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
        #SBATCH --partition=mit_preemptable
        #SBATCH --cpus-per-task=8
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
else
    echo "Config file already exists at $CONFIG_PATH, skipping creation"
fi

cd $SCRATCH_DIR/$DATASET_NAME

# Initialize BABS with the dataset-specific output directory
babs init \
    --datasets BIDS=$SCRATCH_DIR/$DATASET_NAME/$SITE_NAME \
    --container_ds ${PWD}/fs_bidsapp-container \
    --container_name freesurfer-bidsapp-0-1-0 \
    --container_config $SCRATCH_DIR/$DATASET_NAME/config_fs.yaml \
    --processing_level subject \
    --queue slurm \
    $SCRATCH_DIR/$DATASET_NAME/fs_bidsapp_${SITE_NAME}/

cd $SCRATCH_DIR/$DATASET_NAME/fs_bidsapp_${SITE_NAME}
babs submit ${PWD} --all
# babs check-setup ${PWD} --job_test

# # If babs check-setup is successful, submit all jobs
# if [ $? -eq 0 ]; then
#     echo "BABS setup check successful, submitting all jobs..."
#     babs submit $PWD --all
# else
#     echo "BABS setup check failed, not submitting jobs."
#     exit 1
# fi