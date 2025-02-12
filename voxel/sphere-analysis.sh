
#!/bin/bash

###########################################

# Ido Haber / ihaber@wisc.edu
# September 2, 2024
# optimizer for TI-CSC analyzer

# This script performs region of interest (ROI) analysis on NIfTI files for a specific subject.
# It uses spherical masks to extract mean and maximum values from the selected ROIs
# and calculates differential mean values between ROIs across different NIfTI volumes.
# The results are saved in a text file within the designated output directory.

# Arguments:
#   1. subject_id        : The ID of the subject.
#   2. simulation_dir    : The base directory where simulation results are stored.
#   3. selected_rois     : A list of ROIs to analyze.

# Output:
#   - A text file containing the voxel coordinates, mean, and max values for the selected ROIs.
#   - Differential mean values between the selected ROIs.

# Note:
#   The script expects the 'roi_list.json' file to be located in the ../utils directory relative to the simulation directory.
#   It uses FSL tools to perform the analysis, so ensure FSL is installed and configured properly in the environment.
###########################################

# Get the subject ID and simulation directory from the command-line arguments
subject_id="$1"
simulation_dir="$2"
shift 2
selected_rois=("$@")

# Set the designated directory for NIfTI files
nifti_dir="$simulation_dir/sim_${subject_id}/niftis"

# Output directory setup
output_dir="$simulation_dir/sim_${subject_id}/ROI_analysis"

# Define the correct path for the ROI JSON file
roi_file="${simulation_dir}/../utils/roi_list.json"

# Radius for the spherical region (in voxels)
radius=3

# Output file setup
output_file="$output_dir/mean_max_values.txt"
echo "Voxel Coordinates and Corresponding Mean and Max Values for Selected ROIs (Sphere Radius: $radius voxels)" > "$output_file"

# Loop through selected ROIs and volumes
declare -A mean_values

for roi in "${selected_rois[@]}"; do
  location=$(jq -r ".ROIs[\"$roi\"]" "$roi_file")
  echo "" >> "$output_file"
  echo "Voxel Coordinates: ${location} (${roi})" >> "$output_file"

  for volume_file in "$nifti_dir"/*.nii*; do
    volume_name=$(basename "$volume_file" .nii)

    # Use fslmaths to create a spherical mask around the voxel coordinates and extract the mean value
    IFS=' ' read -r vx vy vz <<< "$location"
    temp_sphere="temp_sphere_${volume_name}_${roi}.nii.gz"
    temp_sphere_masked="temp_sphere_masked_${volume_name}_${roi}.nii.gz"

    fslmaths "$volume_file" -mul 0 -add 1 -roi "$vx" 1 "$vy" 1 "$vz" 1 0 1 temp_point -odt float
    fslmaths temp_point -kernel sphere "$radius" -dilM -bin "$temp_sphere" -odt float
    fslmaths "$volume_file" -mas "$temp_sphere" "$temp_sphere_masked"

    mean_value=$(fslstats "$temp_sphere_masked" -M -l 0.0001)
    max_value=$(fslstats "$temp_sphere_masked" -R | awk '{print $2}')

    if [ -z "$mean_value" ]; then
      echo "Error extracting mean value for ${volume_file} at ${location}" >> "$output_file"
      continue
    fi

    mean_values["${volume_name}_${roi}"]=$mean_value

    echo "${volume_name}: mean=$mean_value , max=$max_value" >> "$output_file"

    # Clean up the temporary files
    rm -f temp_point.nii.gz "$temp_sphere" "$temp_sphere_masked"
  done
done

# Calculate and output differential values
echo "" >> "$output_file"
echo "Differential Mean Values between Selected ROIs:" >> "$output_file"

for volume_file in "$nifti_dir"/*.nii*; do
  volume_name=$(basename "$volume_file" .nii)
  for ((i=0; i<${#selected_rois[@]}; i++)); do
    for ((j=i+1; j<${#selected_rois[@]}; j++)); do
      mean_1=${mean_values["${volume_name}_${selected_rois[$i]}"]}
      mean_2=${mean_values["${volume_name}_${selected_rois[$j]}"]}

      if [ -n "$mean_1" ] && [ -n "$mean_2" ]; then
        differential_value=$(echo "$mean_1 - $mean_2" | bc)
        absolute_differential_value=$(echo "$differential_value" | awk '{if ($1<0) print -1*$1; else print $1}')
        echo "${volume_name} (${selected_rois[$i]} vs ${selected_rois[$j]}) = ${absolute_differential_value}" >> "$output_file"
      else
        echo "Error: Missing mean value for ${volume_name} at ${selected_rois[$i]} or ${selected_rois[$j]}" >> "$output_file"
      fi
    done
  done
done

