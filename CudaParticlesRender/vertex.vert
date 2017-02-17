#version 410
layout(location = 0) in vec3 position;
uniform vec3 color;
out vec3 color_out;
void main () {
color_out = color;
gl_Position =vec4 (position, 1.0);
}