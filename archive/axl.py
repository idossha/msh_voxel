from simnibs import mesh_io
mesh_io.write_geo_spheres([[100, 0 ,0], [110, 0, 0]],
'mygeo.geo', values=[1,2], name='myspheres')
mesh_io.write_geo_vectors([[100, 0 ,0], [110, 0, 0]],
[[10, 0 ,0], [0, 10, 0]],
'mygeo.geo', name='myvectors', mode='ba')
