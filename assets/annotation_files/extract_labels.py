
'''
The read_annot function returns three values:
labels: array of label IDs for each vertex
ctab: color table (RGBA values for each label)
names: list of label names
'''


import nibabel as nib

# Load the annotation file
# annot_file = 'lh.aparc.a2009s.annot'
annot_file = 'lh.aparc.DKTatlas.annot'
labels, ctab, names = nib.freesurfer.read_annot(annot_file)

# Display all the label names
for i, name in enumerate(names):
    print(f"{i}: {name.decode('utf-8')}")


