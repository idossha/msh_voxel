
#!/bin/bash
# patch_analysis.sh
#
# This script calculates the peak (max) and average intensity of an electric field 
# image (e.g., TI_field.nii) within a specific cortical patch defined by an atlas.
#
# It accepts three arguments:
#   1. Atlas file (MGZ or NIfTI format)
#   2. Field image (NIfTI format)
#   3. Region label (either a numeric label or a region name, e.g., "ctx-lh-insula")
#
# Example:
#   ./patch_analysis.sh /path/to/aparc.DKTatlas+aseg.mgz \
#       /path/to/101_L_insula_TI_max.nii "ctx-lh-insula"
#
# Requirements:
#   - FreeSurfer (for mri_convert and the FreeSurferColorLUT.txt)
#   - FSL (for fslmaths, fslstats, and flirt)
#
# Exit immediately if a command exits with a non-zero status.
set -e

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 atlas_file field_image region_label"
  exit 1
fi

atlas_file="$1"
field_file="$2"
region_label_input="$3"

# Temporary filenames
tmp_atlas="tmp_atlas.nii.gz"
mask_file="region_mask.nii.gz"

# ---------------------------------------------------------------------------
# Step 1: Convert the atlas from MGZ to NIfTI if needed.
ext="${atlas_file##*.}"
if [ "$ext" = "mgz" ]; then
  echo "Converting atlas from MGZ to NIfTI format..."
  mri_convert "$atlas_file" "$tmp_atlas"
  atlas_nifti="$tmp_atlas"
else
  atlas_nifti="$atlas_file"
fi

# ---------------------------------------------------------------------------
# Step 2: Determine the numeric region label.
# If a numeric value was provided, use it.
# Otherwise, look it up in FreeSurfer's FreeSurferColorLUT.txt.
if [[ "$region_label_input" =~ ^[0-9]+$ ]]; then
  region_label="$region_label_input"
else
  # Ensure FREESURFER_HOME is set.
  if [ -z "$FREESURFER_HOME" ]; then
    echo "Error: FREESURFER_HOME is not set. Please source your FreeSurfer setup script."
    exit 1
  fi

  lut_file="$FREESURFER_HOME/FreeSurferColorLUT.txt"
  if [ ! -f "$lut_file" ]; then
    echo "Error: Lookup table not found at $lut_file"
    exit 1
  fi

  # Use awk to perform a case-insensitive exact match on the region name in the second column.
  # If multiple lines match, we select the first one.
  found_line=$(awk -v region="$(echo "$region_label_input" | tr '[:upper:]' '[:lower:]')" 'tolower($2)==region {print $0}' "$lut_file" | head -n1)
  
  if [ -z "$found_line" ]; then
    echo "Error: Region name '$region_label_input' not found in $lut_file"
    exit 1
  fi

  region_label=$(echo "$found_line" | awk '{print $1}')
  echo "Found region '$region_label_input' with numeric label $region_label from lookup:"
  echo "  $found_line"
fi

# ---------------------------------------------------------------------------
# Step 3: Create a binary mask for the region.
echo "Creating binary mask for region label $region_label from $atlas_nifti ..."
fslmaths "$atlas_nifti" -thr "$region_label" -uthr "$region_label" -bin "$mask_file"

if [ $? -ne 0 ]; then
  echo "Error: Failed to create binary mask from $atlas_nifti."
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 4: Resample the mask to the field image space.
# Although conceptually we only need the field values overlapping the patch,
# FSL voxel-wise operations require that both images share the same grid.
echo "Resampling mask to the field image space..."
# Create an identity transformation matrix for flirt.
cat <<EOF > identity.mat
1 0 0 0
0 1 0 0
0 0 1 0
0 0 0 1
EOF

resampled_mask="region_mask_resampled.nii.gz"
flirt -in "$mask_file" -ref "$field_file" -applyxfm -init identity.mat -interp nearestneighbour -out "$resampled_mask"
# Use the resampled mask for further analysis.
mask_file="$resampled_mask"

# ---------------------------------------------------------------------------
# Step 5: Verify overlapping voxels and compute statistics.
# Count the number of voxels in the field image that fall within the ROI.
overlap_voxels=$(fslstats "$field_file" -k "$mask_file" -V | awk '{print $1}')
echo "Number of overlapping voxels between the field image and ROI: $overlap_voxels"
if [ "$overlap_voxels" -eq 0 ]; then
  echo "Error: No overlapping voxels found. Exiting."
  exit 1
fi

# Calculate the peak (max) and average intensity only in the overlapping region.
max_val=$(fslstats "$field_file" -k "$mask_file" -R | awk '{print $2}')
mean_val=$(fslstats "$field_file" -k "$mask_file" -M)

echo "--------------------------------------"
echo "Region: $region_label_input (Numeric Label: $region_label)"
echo "Peak (Max) Intensity: $max_val"
echo "Average Intensity:  $mean_val"
echo "--------------------------------------"

# ---------------------------------------------------------------------------
# Cleanup temporary files.
rm -f identity.mat "$tmp_atlas" "$resampled_mask"

