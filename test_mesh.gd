extends SceneTree
func _init():
    var st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    st.add_vertex(Vector3(0,0,0))
    st.add_vertex(Vector3(1,0,0))
    st.add_vertex(Vector3(0,1,0))
    st.add_index(0)
    st.add_index(1)
    st.add_index(2)
    var mesh = st.commit()
    var shape = mesh.create_trimesh_shape()
    print(\"Shape: \", shape)
    quit()
