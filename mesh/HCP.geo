
// Load the mesh file
Merge "HCP.msh";

// Set display options
General.Terminal = 1;

// Ensure the 3D element edges and faces are displayed by default
Mesh.VolumeEdges = 1;
Mesh.VolumeFaces = 1;

// Disable 2D element faces and edges
Mesh.SurfaceEdges = 0;
Mesh.SurfaceFaces = 0;

// Assign colors to specific physical groups (replace with your actual tags)
Color{1, 0, 0}{ Physical Volume{1}; } // Red color for Physical Volume 1
Color{0, 1, 0}{ Physical Volume{2}; } // Green color for Physical Volume 2
Color{0, 0, 1}{ Physical Volume{3}; } // Blue color for Physical Volume 3
Color{1, 1, 0}{ Physical Volume{4}; } // Yellow color for Physical Volume 4
Color{1, 0, 1}{ Physical Volume{5}; } // Magenta color for Physical Volume 5

// If you have physical surfaces, you can assign colors to them as well
Color{0, 1, 1}{ Physical Surface{1}; } // Cyan color for Physical Surface 1
Color{0.5, 0.5, 0.5}{ Physical Surface{2}; } // Gray color for Physical Surface 2

