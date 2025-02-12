import nibabel as nib
import numpy as np
import pandas as pd
from nibabel.processing import resample_from_to

'''
Ido Haber
Temporal Interference
September 28th, 2024
nifti analyzer based of the TI field in the HCP atlas
'''


def load_hcp_labels(hcp_txt_file):
    """Load the HCP label file and create a dictionary mapping numbers to label names."""
    labels_dict = {}
    with open(hcp_txt_file, 'r') as file:
        for line in file:
            if line.startswith("#") or not line.strip():
                continue
            parts = line.split()
            label_number = int(parts[0])
            label_name = parts[1]
            labels_dict[label_number] = label_name
    return labels_dict

def extract_first_volume_if_4d(nifti_img):
    """Extract the first volume if the image is 4D."""
    if len(nifti_img.shape) == 4:
        print("Extracting the first volume from 4D NIfTI image.")
        data_3d = nifti_img.get_fdata()[..., 0]
        return nib.Nifti1Image(data_3d, nifti_img.affine)
    return nifti_img

def ensure_3d_affine(affine):
    """Ensure the affine transformation matrix is 4x4."""
    if affine.shape == (5, 5):
        print("Trimming 5x5 affine matrix to 4x4.")
        return affine[:4, :4]
    return affine

def analyze_cortex_parcellation(parcellation_file, ti_field_file, hcp_txt_file, output_csv):
    # Load the HCP label names
    labels_dict = load_hcp_labels(hcp_txt_file)

    # Load the NIfTI files
    parcellation_img = nib.load(parcellation_file)
    ti_field_img = nib.load(ti_field_file)

    # Ensure TI field is 3D by extracting the first volume if it's 4D
    ti_field_img = extract_first_volume_if_4d(ti_field_img)

    # Ensure the affine matrices are 4x4
    parcellation_img._affine = ensure_3d_affine(parcellation_img.affine)
    ti_field_img._affine = ensure_3d_affine(ti_field_img.affine)

    # Resample the TI field data to match the parcellation image if the shapes differ
    if parcellation_img.shape != ti_field_img.shape:
        print("Resampling TI field data to match parcellation data...")
        ti_field_img_resampled = resample_from_to(ti_field_img, parcellation_img)
        ti_field_data = ti_field_img_resampled.get_fdata()
    else:
        ti_field_data = ti_field_img.get_fdata()

    # Get the parcellation data
    parcellation_data = parcellation_img.get_fdata()

    # Find unique regions in the parcellation file
    regions = np.unique(parcellation_data)

    # Prepare the dataframe to store results
    df = pd.DataFrame(columns=['Region', 'Mean', 'Max', 'Min'])

    # Iterate over each region
    for region in regions:
        if region == 0:  # Skip the background
            continue

        # Get the label name from the HCP file
        label_name = labels_dict.get(region, f"Unknown-{region}")

        # Create a mask for the current region
        region_mask = parcellation_data == region

        # Apply the mask to the resampled TI field data
        region_field_values = ti_field_data[region_mask]

        # Remove zero values for statistics calculation
        non_zero_values = region_field_values[region_field_values != 0]

        # Calculate mean, max, and min for the region
        mean_value = np.mean(non_zero_values) if len(non_zero_values) > 0 else 0
        max_value = np.max(non_zero_values) if len(non_zero_values) > 0 else 0
        min_value = np.min(non_zero_values) if len(non_zero_values) > 0 else 0

        # Append the results to the dataframe using pd.concat
        new_row = pd.DataFrame({
            'Region': [label_name],
            'Mean': [mean_value],
            'Max': [max_value],
            'Min': [min_value]
        })
        df = pd.concat([df, new_row], ignore_index=True)

    # Save the results to a CSV file
    df.to_csv(output_csv, index=False)
    print(f'Results saved to {output_csv}')

# Example usage:
parcellation_file = 'HCP_parcellation.nii.gz'
ti_field_file = 'TI_field.nii'
hcp_txt_file = 'HCP.txt'
output_csv = 'cortex_field_analysis.csv'

analyze_cortex_parcellation(parcellation_file, ti_field_file, hcp_txt_file, output_csv)

