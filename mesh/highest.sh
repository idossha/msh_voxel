
#!/bin/bash
# highest.sh
#
# This script takes an atlas file and a field image and determines:
#   1. Which region experiences the highest field peak.
#   2. Which region experiences the highest field average.
#
# The atlas file can be in MGZ (FreeSurfer native) or NIfTI format.
# The field image must be in NIfTI format.
#
# Usage:
#   ./highest.sh atlas_file field_file
#
# Example:
#   ./highest.sh /path/to/aparc.DKTatlas+aseg.mgz /path/to/field_image.nii.gz
#
# Requirements:
#   - FreeSurfer (for mri_convert and FreeSurferColorLUT.txt)
#   - FSL (for fslmaths, fslstats, flirt)
#
# Exit immediately if a command exits with a non-zero status.
set -e

# Check input arguments.
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 atlas_file field_file"
  exit 1
fi

atlas_file="$1"
field_file="$2"

# Check that FREESURFER_HOME is set.
if [ -z "$FREESURFER_HOME" ]; then
  echo "Error: FREESURFER_HOME is not set. Please source your FreeSurfer setup script."
  exit 1
fi

lut_file="$FREESURFER_HOME/FreeSurferColorLUT.txt"
if [ ! -f "$lut_file" ]; then
  echo "Error: Could not find FreeSurferColorLUT.txt in $FREESURFER_HOME."
  exit 1
fi

# Temporary files
tmp_atlas="tmp_atlas.nii.gz"
results_file="region_results.txt"
: > "$results_file"   # Create or empty the results file

# Create an identity transformation matrix for FLIRT.
cat <<EOF > identity.mat
1 0 0 0
0 1 0 0
0 0 1 0
0 0 0 1
EOF

# ---------------------------------------------------------------------------
# Step 1: Convert the atlas if it is in MGZ format.
ext="${atlas_file##*.}"
if [ "$ext" = "mgz" ]; then
  echo "Converting atlas from MGZ to NIfTI format..."
  mri_convert "$atlas_file" "$tmp_atlas"
  atlas_nifti="$tmp_atlas"
else
  atlas_nifti="$atlas_file"
fi

# (Assume that the field image and atlas are in different grids so that resampling is needed.)

# ---------------------------------------------------------------------------
# Step 2: Loop through each region in the LUT.
# We assume that valid LUT lines begin with a digit.
# Each valid line should have the format:
#    <label>  <region_name>  <R> <G> <B> <A>
#
# We skip label 0 (commonly background) and any region with no overlap.
echo "Processing regions from the LUT..."
grep '^[0-9]' "$lut_file" | while read -r line; do
  # Skip empty lines.
  [ -z "$line" ] && continue

  # Read fields.
  label=$(echo "$line" | awk '{print $1}')
  region_name=$(echo "$line" | awk '{print $2}')
  
  # Skip background label 0.
  if [ "$label" -eq 0 ]; then
    continue
  fi

  # Create a temporary binary mask for this region from the atlas.
  region_mask="mask_${label}.nii.gz"
  fslmaths "$atlas_nifti" -thr "$label" -uthr "$label" -bin "$region_mask"

  # Resample the region mask to the field image space.
  region_mask_resampled="mask_${label}_resampled.nii.gz"
  flirt -in "$region_mask" -ref "$field_file" -applyxfm -init identity.mat -interp nearestneighbour -out "$region_mask_resampled"

  # Check for overlap between the field image and the resampled mask.
  vox_info=$(fslstats "$field_file" -k "$region_mask_resampled" -V)
  nvoxels=$(echo "$vox_info" | awk '{print $1}')
  # If there are no voxels, skip this region.
  if [ "$nvoxels" -eq 0 ]; then
    rm -f "$region_mask" "$region_mask_resampled"
    continue
  fi

  # Compute statistics within the resampled mask.
  # fslstats -R returns min and max; we use the second value as the peak.
  peak_val=$(fslstats "$field_file" -k "$region_mask_resampled" -R | awk '{print $2}')
  avg_val=$(fslstats "$field_file" -k "$region_mask_resampled" -M)
    
  # Write results to the temporary results file.
  # Format: label region_name peak_value average_value
  echo "$label $region_name $peak_val $avg_val" >> "$results_file"

  # Remove the temporary masks.
  rm -f "$region_mask" "$region_mask_resampled"
done

# ---------------------------------------------------------------------------
# Step 3: Determine the region with the highest peak and highest average.
if [ ! -s "$results_file" ]; then
  echo "No overlapping regions were found between the field image and atlas."
  rm -f "$tmp_atlas" identity.mat
  exit 1
fi

# Use sort to find the maximum values.
# The results file columns are:
#   1: numeric label, 2: region name, 3: peak, 4: average.
peak_region=$(sort -k3,3n "$results_file" | tail -n 1)
avg_region=$(sort -k4,4n "$results_file" | tail -n 1)

# Extract fields.
peak_label=$(echo "$peak_region" | awk '{print $1}')
peak_name=$(echo "$peak_region" | awk '{print $2}')
peak_value=$(echo "$peak_region" | awk '{print $3}')

avg_label=$(echo "$avg_region" | awk '{print $1}')
avg_name=$(echo "$avg_region" | awk '{print $2}')
avg_value=$(echo "$avg_region" | awk '{print $4}')

# ---------------------------------------------------------------------------
# Step 4: Print the results.
echo "--------------------------------------"
echo "Region with highest field peak:"
echo "  Label: $peak_label"
echo "  Region Name: $peak_name"
echo "  Peak Field Intensity: $peak_value"
echo
echo "Region with highest field average:"
echo "  Label: $avg_label"
echo "  Region Name: $avg_name"
echo "  Average Field Intensity: $avg_value"
echo "--------------------------------------"

# Clean up temporary files.
rm -f "$results_file" "$tmp_atlas" identity.mat

