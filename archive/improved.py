 atlas

def list_available_rois(atlas):
    regions = list(atlas.keys())
    regions_sorted = sorted(regions)
    num_cols = 4  # Number of columns to display
    col_width = max(len(region) for region in regions_sorted) + 2

    print("\nAvailable Regions in the Atlas:\n")
    for i in range(0, len(regions_sorted), num_cols):
        line = ""
        for region in regions_sorted[i:i+num_cols]:
            line += region.ljust(col_width)
        print(line)
    print()

def prompt_user_for_rois(atlas):
    list_available_rois(atlas)
    print("Please enter one or more ROI names separated by commas or spaces:")
    user_input = input("ROIs: ")
    roi_names = [roi.strip() for roi in user_input.replace(',', ' ').split()]
    valid_rois = []
    invalid_rois = []
    for roi in roi_names:
        if roi in atlas:
            valid_rois.append(roi)
        else:
            invalid_rois.append(roi)
    if invalid_rois:
        print(f"Warning: The following ROIs are invalid and will be ignored: {', '.join(invalid_rois)}")
    if not valid_rois:
        print("Error: No valid ROIs provided.")
        sys.exit(1)
    return valid_rois

def create_msh_opt_file(output_file, fields):
    opt_file = f"{output_file}.opt"
    with open(opt_file, 'w') as f:
        f.write(f"View \"Combined_ROI\" {{\n")
        f.write(f"ST(Combined_ROI, {{1}}) ;\n")
        f.write(f"}};\n\n")
        for field_name in fields:
            f.write(f"View \"{field_name}\" {{\n")
            f.write(f"ST({field_name}, {{1}}) ;\n")
            f.write(f"Range [0:1];\n")  # Adjust range as needed
            f.write(f"Color Rainbow;\n")
            f.write(f"}};\n\n")
    print(f"Visualization options saved to {opt_file}")

def visualize_rois(gm_surf, atlas, rois, output_file):
    for idx, roi_name in enumerate(rois, start=1):
        roi = atlas[roi_name]
        field_label = f'ROI_{idx}_{roi_name}'
        gm_surf.add_node_field(roi, field_label)
    
    try:
        num_nodes = gm_surf.nodes.nr
    except AttributeError:
        print(f"Error: Unable to determine the number of nodes.")
        sys.exit(1)

    combined_roi = np.zeros(num_nodes, dtype=bool)
    for roi_name in rois:
        combined_roi = combined_roi | atlas[roi_name]
    
    gm_surf.add_node_field(combined_roi, 'Combined_ROI')

    if not output_file.endswith('.geo') and not output_file.endswith('.msh'):
        output_file += '.geo'
    
    try:
        gm_surf.write(output_file)
        # Pass the fields you want to visualize in the .msh.opt file
        create_msh_opt_file(output_file, ['E_magn', 'E_normal', 'E_tangent', 'E_angle', 'Combined_ROI'])
        print(f"Visualization saved to {output_file}")
    except Exception as e:
        print(f"Error saving file: {e}")
        sys.exit(1)

def perform_analysis(gm_surf, atlas, rois, field_name):
    if field_name not in gm_surf.field:
        print(f"Error: Field '{field_name}' not found in the mesh.")
        sys.exit(1)
    
    node_areas = gm_surf.nodes_areas()
    results = {}
    for roi_name in rois:
        roi = atlas[roi_name]
        field_values = gm_surf.field[field_name][roi]
        weights = node_areas[roi]
        if np.sum(weights) == 0:
            print(f"Warning: Total area for ROI '{roi_name}' is zero. Skipping.")
            continue
        mean_value = np.average(field_values, weights=weights)
        min_value = np.min(field_values)
        max_value = np.max(field_values)
        results[roi_name] = {"mean": mean_value, "min": min_value, "max": max_value}
    return results

def prompt_for_input(prompt_message, default=None, allow_empty=False):
    while True:
        if default:
            user_input = input(f"{prompt_message} [{default}]: ")
            if user_input.strip() == '':
                user_input = default
        else:
            user_input = input(f"{prompt_message}: ")
        
        if user_input.strip() == '' and not allow_empty:
            print("Input cannot be empty. Please try again.")
        else:
            return user_input.strip()

def main():
    print("=== ROI Analysis of Electric Field Using SimNIBS ===\n")
    
    subjectID = prompt_for_input("Enter Subject ID (e.g., 101)", default="101")
    atlas_name = prompt_for_input("Enter Atlas Name (e.g., HCP_MMP1)", default="HCP_MMP1")
    default_msh_path = os.path.join('tdcs_simu', 'subject_overlays',
                                    f'{subjectID}_TDCS_1_scalar_central.msh')
    msh_path = prompt_for_input("Enter path to the .msh file", default=default_msh_path, allow_empty=True)
    if msh_path == '':
        msh_path = default_msh_path
    
    gm_surf = load_msh_file(subjectID, msh_path)
    atlas = load_atlas(atlas_name, subjectID)
    selected_roi_names = prompt_user_for_rois(atlas)
    field_name_default = 'E_magn'
    field_name = prompt_for_input(f"Enter Field Name to analyze", default=field_name_default, allow_empty=True)
    if field_name == '':
        field_name = field_name_default
    
    output_geo_default = 'merged_visualization.geo'
    output_geo = prompt_for_input("Enter Output .geo file name", default=output_geo_default, allow_empty=True)
    if output_geo == '':
        output_geo = output_geo_default

    visualize_rois(gm_surf, atlas, selected_roi_names, output_geo)
    
    analysis_results = perform_analysis(gm_surf, atlas, selected_roi_names, field_name)
    
    print("\n=== Analysis Results ===")
    for roi_name, values in analysis_results.items():
        print(f"ROI: {roi_name}, Mean {field_name}: {values['mean']:.4f}, Min: {values['min']:.4f}, Max: {values['max']:.4f}")
    print("\n=== Analysis Complete ===")

if __name__ == '__main__':
    main()
