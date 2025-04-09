#!/bin/bash
# Wrapper script to process multiple BIDS datasets
#!/bin/bash
if [ -f ".env" ]; then
    source .env
fi

# Check if datasets file and dataset name are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <datasets_file> <dataset_name>"
    echo "  datasets_file: A text file with one dataset path per line"
    echo "  dataset_name: The name of the dataset (used for directory structure)"
    exit 1
fi

DATASETS_FILE="$1"
DATASET_NAME="$2"

# Check if file exists
if [ ! -f "$DATASETS_FILE" ]; then
    echo "Error: Dataset list file not found: $DATASETS_FILE"
    exit 1
fi

# Read each line from the file and process each dataset
while IFS= read -r dataset_path_raw; do
    # Remove leading and trailing whitespace
    dataset_path=$(echo "$dataset_path_raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    
    # Skip empty lines and comments
    [[ -z "$dataset_path" || "$dataset_path" =~ ^#.* ]] && continue
    
    echo "==============================================="
    echo "Processing site: $dataset_path for dataset: $DATASET_NAME"
    echo "==============================================="
    
    # Call the main script with the dataset path and dataset name
    ./fs_babs_script.sh "$DATAS_DIR/$dataset_path" "$DATASET_NAME"
    
    # Optional: Add a delay between processing datasets
    # sleep 10
    
    echo "Completed processing site: $dataset_path"
    echo ""
done < "$DATASETS_FILE"

echo "All sites for dataset $DATASET_NAME have been processed!"